require 'time'; require 'cgi'
$: << "vendor"
require 'bluecloth'; require 'rubypants'; require 'htemplate'
BlueCloth::EmptyElementSuffix.replace(">")

Dir.mkdir("html")  rescue true

def File.write(name, content)
  File.open(name, "wb") { |out| out << content }
  puts name
end

def dep(dst, *srcs)
  yield dst  unless srcs.all? { |src|
               (File.mtime(src) < File.mtime(dst) rescue false) }
end

def parse(f)
  head, body = File.read(f).split("\n\n", 2)  rescue (return nil)
  entry = {:body => body, :id => File.basename(f, ".entry"), :file => f}
  head.scan(/(\w+):\s*(.*)/) { entry[$1.downcase.to_sym] = $2 }
  entry[:date] = Time.parse(entry[:date])  if entry[:date]
  entry[:title] = entry[:date].strftime("%d%b%Y").downcase  if entry[:date]
  entry
end

Entry = Hash.new { |h, k| h[k] = parse k }
ENTRIES = Dir.glob("entries/*.entry").map { |x| Entry[x] }.
                                      sort_by { |f| f[:date] }.reverse
Entry.values.each { |v| Entry[v[:id]] = v }

class SpanBlueCloth < BlueCloth
  def apply_block_transforms(text, rs)
    text                        # we don't do blocks
  end
end

class InlineMath < String
  MATH_TEX = 'http://vuxu.org/~chris/mathtex/mathtex.cgi?' +
    CGI.escape('\textstyle{}\usepackage{color}\color{white}\rule[-0.333em]{0.01pt}{1.2em}\color{black}')
  
  def to_html
    gsub(/\$(.*?)\$/) {
      html = CGI.escapeHTML($1)
      formula = CGI.escape($1).gsub('+', '%20')
      %{<img class="inline-math" alt="#{html}" src="#{MATH_TEX}#{formula}">}
    }
  end
end

class Dots < String
  MATH_TEX = "http://vuxu.org/~chris/mathtex/mathtex.cgi?"

  def to_html
    gsub(/^\.(\w+)([^\n]*?)\n(.*?)^\.\1\.$/m) {
      name, args, body = $1, $2, $3
      case name
      when "link"
        title, desc = body.split("|", 2)
        # why does bluecloth need those div?
        %{<p class="link"><span><a href="#{args.strip}">#{title.strip}</a>#{SpanBlueCloth.new(desc).to_html}</span></p>}
      when "quote"
        if args.strip.empty?
          src = ""
        else
          src = %{<span class="source">&#x2014; #{args.strip}</span>}
        end
        %{<div class="quote">#{BlueCloth.new((body + src).gsub(/^.*$/, '> \&  ')).to_html}</div>}
      when "math"
        body << "\\eqno{#{args.strip}}"  unless args.strip.empty?
        %{<div class="math"><img alt="#{CGI.escapeHTML body}" src="#{MATH_TEX}#{CGI.escape(body).gsub('+', '%20')}"></div>}
      else
        %{<div class="#{name}">#{BlueCloth.new(Dots.new(body).to_html).to_html}</div>}
      end
    }
  end
end

def format(e)
  RubyPants.new(
  BlueCloth.new(
  Dots.new(
  InlineMath.new(
    e[:body]
  ).to_html).to_html).to_html).to_html
end

def template(template, data)
  HTemplate.new(File.read(template), template).expand(data)
end

def group(entries, &block)
  r = {};  entries.each { |e| (r[block[e]] ||= []) << e };  r
end

def inner_sort(group, &block)
  group.each { |key, entries| entries.sort_by(&block) }
end

def outer_sort(group, &block)
  group.sort_by(&block)
end

def chain(group, name)
  group.each_with_index { |(key, entries), i|
    entries.each { |e|
      e[:"next_by_#{name}"] = group[i+1][0]  if group[i+1]
      e[:"prev_by_#{name}"] = group[i-1][0]  if i > 0
    }
  }
end

def deps(e)
  [e[:id], e[:next_by_date], e[:prev_by_date]].compact.map {|z| Entry[z][:file] }
end

single_by_date = group(ENTRIES) { |e| e[:id] }
single_by_date = outer_sort(single_by_date) { |k,e| e.first[:date] }
chain(single_by_date, "date")
      
single_by_date.each { |date, entries|
  entry = entries.first
  dep "html/#{entry[:id]}.html", "template/single.ht", *deps(entry) do |dst|
    File.write(dst, template("template/single.ht", entry))
  end
}

monthly = group(ENTRIES) { |e| e[:date].strftime("%Y-%m") }
inner_sort(monthly) { |e| e[:date] }
monthly = outer_sort(monthly) { |k,e| e.first[:date] }
chain(monthly, "month")

monthly.each { |month, entries|
  entry = entries.first
  dep "html/#{month}.html", "template/monthly.ht", *deps(entry) do |dst|
    File.write(dst, template("template/monthly.ht", :entries => entries, :month => month))
  end
}

front = ENTRIES.first(2)  #(10)
d = front.map { |e| e[:file] }
dep "html/index.html", "template/front.ht", *d do |dst|
  File.write(dst, template("template/front.ht", :entries => front, :next => monthly.last))
end

feed = ENTRIES.first(20)
d = feed.map { |e| e[:file] }
dep "html/index.atom", "template/atom.ht", *d do |dst|
  File.write(dst, template("template/atom.ht",
                           :entries => feed, :time => Time.now))
end

d = ENTRIES.map { |e| e[:file] }
dep "html/all.html", "template/all.ht", *d do |dst|
  File.write(dst, template("template/all.ht", :entries => ENTRIES))
end

system "rsync -r data/ html"
