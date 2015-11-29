require 'nokogiri'
require 'byebug'
require 'net/http'
require "open-uri"

@base_url = 'hubblesite.org'
@download_urls = ['/gallery/album/entire']
@image_page_urls = []
@processed_urls = []

def visit_gallery_page url
  res = Net::HTTP.get(@base_url, url)
  html_doc = Nokogiri::HTML(res)
  image_links = html_doc.css("#ListBlock a").map{|l| l.attr("href")}
  page_links = html_doc.css("a.next-page").map{|l| l.attr("href")}

  # append  links to appropriate queue
  @processed_urls << url
  @download_urls = (@download_urls + page_links - @processed_urls)
  @download_urls.uniq!
  @image_page_urls = (@image_page_urls + image_links - @processed_urls).uniq
  @image_page_urls.uniq!
end

def visit_image_page url
  res = fetch(url)
  html_doc = Nokogiri::HTML(res.body) if res.is_a?(Net::HTTPSuccess)

  begin
    link = html_doc.css(".button-holder").first.css("a").last
  rescue Exception => e
    link = nil
  end

  #style one 
  if link.nil?
    link = html_doc.css(".inline-links").last
		byebug if link.nil?
    res = fetch(link.attr("href"))
    html_doc = Nokogiri::HTML(res.body) if res.is_a?(Net::HTTPSuccess)

    img = html_doc.css(".subpage-body img").first
  else # style two
    res = fetch(link.attr("href")) 
    html_doc = Nokogiri::HTML(res.body) if res.is_a?(Net::HTTPSuccess)
    img = html_doc.css(".image-view img").first
  end

  alt = img.attr("alt")
  src = img.attr("src")
  if alt.nil?
    fName = File.basename(src)
  else
    fName = alt.gsub(/\s/, "-")+".jpg"
  end

	File.open("./dest/#{fName}", "wb") do |file|
    open(src) do |f|
		  file.write f.read
    end
	end
end

def fetch(uri_str, limit = 10)
	uri_str = "http://#{@base_url}#{uri_str}"

  # You should choose better exception.
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  url = URI.parse(uri_str)
  req = Net::HTTP::Get.new(url.path, { 'User-Agent' => 'hubble-fetcher'})
  response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  case response
  when Net::HTTPSuccess     then response
  when Net::HTTPRedirection
    puts "Redirect Location: #{response['location']}"
    fetch(response['location'], limit - 1)
  else
    response.error!
  end
end

while !@download_urls.empty?
  url = @download_urls.shift
  puts url
  visit_gallery_page url
end

workers = (0...8).map do
  Thread.new {
    while url = @image_page_urls.pop
    visit_image_page url
    end
  }
end

workers.map(&:join)
