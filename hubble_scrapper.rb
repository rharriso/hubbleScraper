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
  res = fetch("http://#{@base_url}#{url}")
  html_doc = Nokogiri::HTML(res.body) if res.is_a?(Net::HTTPSuccess)
  link = html_doc.css(".button-holder:first a:last").last

  #style one 
  if link.nil?
    link = html_doc.css(".inline-links a:last").last
		return if link.nil?
    res = fetch(link.attr("href"))
    html_doc = Nokogiri::HTML(res.body) if res.is_a?(Net::HTTPSuccess)

    img = html_doc.css(".subpage-body img").first
  else # style two
    res = fetch(link.attr("href")) 
    html_doc = Nokogiri::HTML(res.body) if res.is_a?(Net::HTTPSuccess)
    img = html_doc.css(".image-view img").first
  end

  alt = img.attr("alt")
  fName = alt.gsub(/\s/, "-")+".jpg"
  src = img.attr("src")
  puts src, fName
  resp = fetch(src)

	File.open("./dest/#{fName}", "wb") do |file|
		resp.read_body do |segment|
		  file.write segment
    end
	end
end

def fetch(uri_str, limit = 10)
	uri_str = "http://#{@base_url}#{uri_str}"
  puts uri_str

  # You should choose better exception.
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  url = URI.parse(uri_str)
  req = Net::HTTP::Get.new(url.path, { 'User-Agent' => 'hubble-fetcher'})
  response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
  case response
  when Net::HTTPSuccess     then response
  when Net::HTTPRedirection
    puts "Location", response['location']
    fetch(response['location'], limit - 1)
  else
    puts url
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
