Encoding.default_internal = 'UTF-8'
require 'rubygems'
require 'bundler/setup'
Bundler.require
require 'digest'
require 'sinatra'
require "sinatra/reloader" if development?

def build_s3_key(url, hash)
  host = URI.parse(url).host
  return "#{host}/#{hash}"
end

def build_public_url(region, bucket, key, content_type)
  return "https://s3-#{region}.amazonaws.com/#{bucket}/#{key}.#{content_type}"
end

post '/archive' do
  content_type :json

  if request&.content_type.to_s.start_with? "application/json"
    begin
      payload = JSON.parse(request.env["rack.input"].read)
    rescue 
      return {error: "Error parsing request. Ensure you send a JSON or form-encoded payload"}.to_json
    end
  else
    payload = params
  end

  # Check required parameters
  required = [
    'key_id',
    'secret_key',
    'region',
    'bucket',
    'url'
  ]
  required.each do |field|
    if !payload[field]
      return {error: "Missing field: #{field}"}.to_json
    end
  end

  image_url = payload['url']

  # Fetch the image
  response = HTTParty.get image_url, follow_redirects: true

  if response.code != 200
    return {error: "URL return invalid status code: #{response.code}"}.to_json
  end

  # Check content type
  # Either Content-Type or Content-Disposition headers are checked
  extension = false
  if c=response.headers['content-type']
    if m=c.match(/image\/(png|jpg|jpeg|gif|ico|svg)/)
      extension = m[1]
    end
  end

  if extension == false && (c=response.headers['content-disposition'])
    if m=c.match(/filename=.+\.(png|jpg|jpeg|gif|ico|svg)/)
      extension = m[1]
    end
  end

  if !extension
    return {error: "Input was not a recognized image type"}.to_json
  end

  extension = 'jpg' if extension == 'jpeg'

  # Calculate hash of image contents and check if it already exists in the bucket
  hash = Digest::SHA256.hexdigest response.body

  key = build_s3_key image_url, hash
  # puts "#{key}.#{extension}"

  s3 = S3::Service.new(access_key_id: payload['key_id'], secret_access_key: payload['secret_key'])
  bucket = s3.buckets.find(payload['bucket'])

  begin
    object = bucket.objects.find "#{key}.meta"
    # Look up the type in the meta file
    if m=object.content.match(/type: (.+)/)
      ext = m[1]
    else
      ext = extension
    end

    public_url = build_public_url payload['region'], payload['bucket'], key, ext
    # If no exception is thrown, the object already exists so return it now
    return {url: public_url, new: false}.to_json
  rescue

    public_url = build_public_url payload['region'], payload['bucket'], key, extension
    # puts public_url

    image_data = response.body

    # Resize the image if requested
    if ['png','jpg','gif'].include?(extension) && payload['max_height']
      img = Magick::Image.from_blob(response.body).first
      img.change_geometry!("x#{payload['max_height']}>") { |cols, rows, img|
        img.resize! cols, rows
      }
      image_data = img.to_blob
    end

    # Store the object and metadata in s3 now
    metadata = "date: #{Time.now.strftime('%Y-%m-%dT%H:%M:%S')}\n"\
      "type: #{extension}\n"\
      "url: #{image_url}\n"
    metadata_obj = bucket.objects.build("#{key}.meta")
    metadata_obj.content = metadata
    metadata_obj.content_type = 'text/plain'
    metadata_obj.acl = :public_read
    metadata_obj.save

    image_obj = bucket.objects.build("#{key}.#{extension}")
    image_obj.content = image_data
    image_obj.content_type = "image/#{extension == 'jpg' ? 'jpeg' : extension}"
    image_obj.acl = :public_read
    image_obj.save

    return {url: public_url, new: true}.to_json
  end

end
