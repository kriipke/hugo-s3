# Static Site Generation Toolchain: Asciidoctor + Hugo + AWS Cloundfront

This git repository includes the following tools that give you everything you need to create, edit, maintain and depoy a website using Hugo+asciidoctor and deploy it to a domain name purchased on (or transfered to) AWS:

1. An interative shell script to automate the setup of the required AWS resources (S3 bucket, logging, TLS certificate & Cloudfront distribution).
2. A `Dockerfile` for a Docker container with all the `Hugo` & `asciidoctor` tools needed to actually build the website.
3. a `Makefile` that will allow you to, among other things, painlessly test and edit your website via Docker by simply running `make` in the correct directory.

## Cloudfront setup script

If you don't already have a TLS enabled Cloudfront distrution setup, this bash file contains all the required code to get one setup -- all you need is a domain name from [Route53](https://aws.amazon.com/route53/).

When you run it you will be prompted for a few variables but the only one you really need is the domain name you want to deploy your Hugo site at. The rest of the prompts have default values which work fine unless you have special requirements.

The script generates a comprehensive logfile, `cloudfront_generation.log`, so you can verify any changes that were made or AWS resources that were created.

The final output of the script is a Hugo configuration file snippet that can be copied into your main Hugo configuration file for later use with `make deploy` (see below)

Why `Cloudfront`?
Deploying Hugo websites on AWS S3 has become a popular alternative to hosting your Hugo site on a webserver, and in order to host a TLS enabled website via S3 a Cloudfront distribution is required. Also, `Cloudfront` comes with some cool perks, notably quicker content distribution as it's proper CDN.

## `Makefile` workflow

When properly setup, you can simply `cd` to the correct directory for your Hugo project and run `make` and then go to your browser and view your website live as changes are being made at `http://localhost:1313` without having to worry about have any Hugo or asciidoctor software on your local machine at all. Sounds great, right?

When using the `Makefile`, the source code for the Hugo project you want to work with in a directory named `src/` located in the same directory as the `Makefile` 

If you have multiple Hugo sites you would like to use with this workflow, it's easiest to clone this repo and link the `Makefile` into the parent directory ofeach projects source, e.g.:

```
git clone https://github.com/l0xy/hugo-s3.git
ln -s hugo-s3/Makefile site1.com/
ln -s hugo-s3/Makefile site2.com/
```

where the directories `site1.com/` and `site2.com/` have the structure:
```
./site1.com/
├───Makefile -> /path/to/this/repo/Makefile
└───src/
    ├───config/
    ├───content/
    ├───layouts/
    └───static/ 

./site2.com/
├───Makefile -> /path/to/this/repo/Makefile
└───src/
    ├───config/
    ├───content/
    ├───layouts/
    └───static/ 
```

This way you can just `cd` to the directory named after the site you're attempting to work on and run `make` to serve the site locally.

### `Makefile` targets

#### `make image`

Generates a Docker image named `hugo-s3` that contains everything you need to generate the Hugo site you've got the source for on your local machine.

This image is also available via `docker pull l0xy/hugo-s3`, so you don't typically need to use this command unless you've edited the Dockerfile yourself to add some extra functionality to Hugo.

#### `make serve`

Since this is the default target, you can serve the site locally simply by running `make`. This allows live editing so you can test the site as you're editing/testing/creating it; the site is accessible from `http://localhost:1313` in your browser.

#### `make deploy`

This just generates and deploys the site to the first deployment listed in your hugo configuration. If you generated a Cloudfront deployment using the bash script that comes with this repository your deployment section will look very similar to this:
```
    [deployment]
      [[deployment.targets]]
      name = "S3 hosted Hugo site"
      URL = "s3://<Bucket Name>?region=<AWS region>"
      cloudFrontDistributionID = <ID>
```

Before running `make deploy` it is assumed that you have:
- an s3 bucket configured properly (publicly accessible, configured to host a static site, etc); see [here](https://capgemini.github.io/development/Using-S3-and-Hugo-to-Create-Hosting-Static-Website/), or use the script that comes in this repository.
 - a file `~/.aws/credentials` containing the credentials needed to access said bucket (the simplest way to do that is just to configure the `aws-cli` on your machine, however it's not required as `aws-cli` is run from the Docker container)

## Docker image

If you're not interested in downloading the workflow tools in the git repository above and you just want to start using this Docker you built via the Dockerfile or downloaded via `docker pull l0xy/hugo-s3`, here's what you need to know:
 
This docker image is configured with 3 main tools: 
  1. [Hugo extended](https://gohugo.io/getting-started/installing/) - pretty much the same as regular Hugo, but includes support for [Sass/SCSS](https://sass-lang.com/)
  2. [asciidoctor](https://asciidoctor.org/) - provides the option of writing your Hugo site in a much richer markup language than traditional Markdown
  3. [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html#cliv2-linux-install) - for S3 deployment

Additionally these ruby gems have been installed for use with asciidoctor:

- `asciidoctor-rouge`
- `asciidoctor-interdoc-reftext`
- `asciidoctor-diagram asciidoctor-html5s`

If you want to use Hugo with Markdown instead of asciidoctor that's fine, the other softwares won't get in your way or prevent you from doing so.

