ca3db
=====

ca3db is a "content-addressable avatar archive", intended for permanently storing
multiple versions of user avatars found on social networks and websites.

[Heroku](https://heroku.com)[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

## API

ca3db exposes an HTTP API for archiving images. Once deployed, there is just one API endpoint which accepts the following parameters as a JSON payload:

`POST /archive`

* `url`: The URL of the image to store
* `bucket`: The name of the S3 bucket to store the image in
* `region`: The Amazon region that the S3 bucket lives in
* `key_id`: An Amazon API ID that has write access to the S3 bucket
* `secret_key`: The secret key for the above ID
* `max_height` (optional): If specified, the image will be resized to this maximum height if larger

The service will fetch the URL, and store the image in the S3 bucket. The filename is a
hash of the file contents, so calling this multiple times with the same image will not
store duplicate photos. Similarly, if the same URL gets replaced with a different image,
both images will be stored at different URLs.

The response will be a JSON payload with the URL of the archived image, e.g.:

```json
{
  "url":"https://s3-us-west-2.amazonaws.com/ca3db/kylewm.com/dcffbb0712bbccc3ed94fc0f0c873ce8fde83d0cc3474fff93109042c378e2f4.jpeg"
}
```
