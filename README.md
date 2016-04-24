# infrastructure

This repo contains a terraform template to automatically deploy all the other stuff to aws

see main.tf for wayyy more details

## architecture

in order to get this project done quickly and make sure it costs no $ to operate forever, we're leaning pretty heavily on Amazon Web Services, specifically two products:

**s3**

s3 stands for "simple storage service". You make "buckets," which are kinda like folders, and then you put "objects" in them, which are exactly like files. 

You can make a bucket public and point a domain name at it to host a website. If you did so, and your bucket was called "fabulousartist.com" and then an object called "blog/my-first-post.html", you'd be able to browse to "http://fabulousartist.com/blog/my-first-post.html" and see that file.

You can make a bucket private or write-only to make a file dropbox.

It's very cheap: 3 cents per gigabyte in storage and a penny per 25,000 requests.

**lambda**

A web server is a program that's running on some computer, listening for requests.

A lambda function is a program that amazon starts up *when you get a request*, and that quits immediately after. They usually work like web pages: you call the function by requesting a particular url, the function does a thing, and then sends you back a page with some information.

You only have to pay for the milliseconds in which your program is running.

Another advantage is that if you get a million requests at the same time, amazon just runs your program on a million computers, no problem. If you were renting computers individually, as is standard practice, you'd better have enough of them on hand already.

A disadvantage is that there isn't (to my knowledge) a good way of running lambda functions outside of Amazon.

Another disadvantage is that when your server is a program that runs for a long time, you don't really need to care about how long it takes to start up, connect to external resources, whatever. With lambda, you really do. This can make it slow if you aren't careful. Especially since you can't rely on storing information in one computer's RAM between requests, so persistent information inherently means you have to connect to something external.

**also**

Amazon likes giving names to things. Idk if I'd call these "products" really, but we're also using:

- _API Gateway_ for pointing urls at lambda functions
- _route53_ for pointing domain names at s3 buckets
- _IAM_ for controlling security and permissions

### the plan

**the website**

The website is some html and javascript files in an s3 bucket called "radblock.xyz". It'll link to the browser plugin or whatever, maybe have a video, and point ppl towards a page for uploading gifs.

**uploading gifs**

Gifs are kept in an s3 bucket called "gifs.radblock.xyz". When someone uploads a gif, javascript in their browser calls two lambda functions:

- first, a function verifies their payment with [stripe](//stripe.com), and gets back some information about the transaction: a user id, zip code, etc. It then saves a file called that user's id into a separate s3 bucket called "radblock-users".
- then, a function authorizes their s3 upload and passes back the authorization token.

then the browser uploads the file to s3.

the "gifs.radblock.xyz" s3 bucket is configured to delete all files after a week.

The "radblock-users" s3 bucket is configured to delete all files after 24 hours: this is how we'll handle upload limiting. If there's a file in the bucket with your name on it, you can't upload another gif.

**gif rotator**

We have another s3 bucket called "random.radblock.xyz". Every minute or so, a lambda function is scheduled to find all the files in the "gifs.radblock.xyz" bucket, randomize their order, and save a list of their urls into "random.radblock.xyz/thelist". It'll look something like this:

```json
[
  "http://gifs.radblock.xyz/some.gif",
  "http://gifs.radblock.xyz/another.gif",
  "http://gifs.radblock.xyz/one-last.gif"
]
```

**browser plugin**

whenever you go to a page, the browser plugin will download the latest list of gifs from "random.radblock.xyz/thelist", and then insert those gifs onto the page.
