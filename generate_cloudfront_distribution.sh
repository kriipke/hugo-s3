#!/usr/bin/env bash

set -x 

DOMAIN_NAME=
REGION=
INDEX_DOCUMENT=index.html
ERROR_DOCUMENT=404.html

if [ -z "$DOMAIN_NAME" ]; then
	echo "Edit the first line of this script to add the domain" \
		"name you registered on Route53 for your website."
	exit 1
fi

if [ -z "$REGION" ]; then
	echo "Edit the second line of this script to add the AWS" \
		"region in which you want to deploy your Cloudfront distribution."
	exit 1
fi

CONTENT_BUCKET=$DOMAIN_NAME
LOGGING_BUCKET=$CONTENT_BUCKET-logs

create_content_bucket () {
	local BUCKET_POLICY WEBSITE_CONFIG

	echo "Creating bucket that will be hosting $DOMAIN_NAME.."

    IFS=$'\n' read -r -d '' BUCKET_POLICY <<-EOF
    {
	"Version": "2012-10-17",
	"Statement": [
	    {
		"Sid": "PublicReadGetObject",
		"Effect": "Allow",
		"Principal": "*",
		"Action": [
		    "s3:GetObject"
		],
		"Resource": [
		    "arn:aws:s3:::$CONTENT_BUCKET/*"
		]
	    }
	]
    }
	EOF

    IFS=$'\n' read -r -d '' WEBSITE_CONFIG <<-EOF
    {
	"IndexDocument": {
	    "Suffix": "$INDEX_DOCUMENT"
	},
	"ErrorDocument": {
	    "Key": "$ERROR_DOCUMENT"
	},
	"RoutingRules": [
	    {
		"Redirect": {
		    "ReplaceKeyWith": "$INDEX_DOCUMENT"
		},
		"Condition": {
		    "KeyPrefixEquals": "/"
		}
	    }
	]
    }
	EOF

    if ! aws s3 ls "$LOGGING_BUCKET" 2>/dev/null; then
	aws s3api create-bucket \
	    --bucket $CONTENT_BUCKET \
	    --region $REGION
    fi

    aws s3api put-bucket-policy \
	--bucket $CONTENT_BUCKET \
	--policy "$BUCKET_POLICY"

    aws s3api put-bucket-website \
	--bucket $CONTENT_BUCKET \
	--website-configuration "$WEBSITE_CONFIG"
}


configure_logging () {
	local LOGGING_POLICY

	echo "Configuring logging for bucket that will be hosting $DOMAIN_NAME.."

	IFS=$'\n' read -r -d '' LOGGING_POLICY <<-EOF
	{
	  "LoggingEnabled": {
		"TargetBucket": "$LOGGING_BUCKET",
		"TargetPrefix": "logs/"
	  }
	}
	EOF

	if ! aws s3 ls $LOGGING_BUCKET 2>/dev/null; then
		aws s3api create-bucket \
			--bucket $LOGGING_BUCKET \
			--region $REGION
	fi

	# the put-bucket-acl command is required to grant S3's log delivery
	# system the necessary permissions (write and read-acp permissions)
	aws s3api put-bucket-acl \
		--bucket $LOGGING_BUCKET \
		--grant-write URI=http://acs.amazonaws.com/groups/s3/LogDelivery \
		--grant-read-acp URI=http://acs.amazonaws.com/groups/s3/LogDelivery

	aws s3api put-bucket-logging \
		--bucket $CONTENT_BUCKET \
		--bucket-logging-status "$LOGGING_POLICY"
}

request_certificate () {
	local RECORD_NAME RECORD_VALUE MAKE_CNAME_RECORD

	echo "Requesting certificate for $DOMAIN_NAME"
	
	CERT_ARN=$( aws acm request-certificate \
		--domain-name "$DOMAIN_NAME" \
		--subject-alternative-names "www.$DOMAIN_NAME" \
		--validation-method DNS \
		--idempotency-token "$(date +%s)" \
		| jq '.CertificateArn' )

	RECORD_NAME=$( aws acm describe-certificate "$CERT_ARN" \
		| jq '.Certificate.DomainValidationOptions[0].ResourceRecord.Name' )
	RECORD_VALUE=$( aws acm describe-certificate "$CERT_ARN" \
		| jq '.Certificate.DomainValidationOptions[0].ResourceRecord.Value' )
	ZONE_ID=$( aws route53 list-hosted-zones \
		| jq -r '.HostedZones | .[] | select( .Name | test("'$DOMAIN_NAME'")) | .Id' \
		| cut -d/ -f3 )

	IFS=$'\n' read -r -d '' MAKE_CNAME_RECORD <<-EOF
	{
		"HostedZoneId": "$ZONE_ID",
		"ChangeBatch": {
			"Comment": "",
			"Changes": [
				{
					"Action": "UPSERT",
					"ResourceRecordSet": {
						"Name": "$RECORD_NAME",
						"Type": "CNAME",
						"TTL": 300,
						"ResourceRecords": [
							{
								"Value": "$RECORD_VALUE"
							}
					}
				}
			]
		}
	}
	EOF

	aws route53 change-resource-record-set "$MAKE_CNAME_RECORD"
}


configure_cloudfront () {
	local CLOUDFRONT_CONFIG
	
	echo "Configuring Cloudfront distribution..."

	IFS=$'\n' read -r -d '' CLOUDFRONT_CONFIG <<-EOF
	{
		"Comment": "Hugo Static Hosting on S3",
		"Logging": {
			"Bucket": "$LOGGING_BUCKET.s3.amazonaws.com",
			"Prefix": "cdn-cf/",
			"Enabled": true,
			"IncludeCookies": false
		},
		"Origins": {
			"Quantity": 1,
			"Items": [
				{
					"Id":"$CONTENT_BUCKET-origin",
					"OriginPath": "",
					"CustomOriginConfig": {
						"OriginProtocolPolicy": "http-only",
						"HTTPPort": 80,
						"OriginSslProtocols": {
							"Quantity": 3,
							"Items": [
								"TLSv1",
								"TLSv1.1",
								"TLSv1.2"
							]
						},
						"HTTPSPort": 443
					},
					"DomainName": "$DOMAIN_NAME.s3-website-$BUCKET_REGION.amazonaws.com"
				}
			]
		},
		"DefaultRootObject": "$INDEX_DOCUMENT",
		"PriceClass": "PriceClass_All",
		"Enabled": true,
		"CallerReference": "1592125711",
		"DefaultCacheBehavior": {
			"TargetOriginId": "$CONTENT_BUCKET-origin",
			"ViewerProtocolPolicy": "redirect-to-https",
			"DefaultTTL": 1800,
			"AllowedMethods": {
				"Quantity": 2,
				"Items": [
					"HEAD",
					"GET"
				],
				"CachedMethods": {
					"Quantity": 2,
					"Items": [
						"HEAD",
						"GET"
					]
				}
			},
			"MinTTL": 0,
			"Compress": true,
			"ForwardedValues": {
				"Headers": {
					"Quantity": 0
				},
				"Cookies": {
					"Forward": "none"
				},
				"QueryString": false
			},
			"TrustedSigners": {
				"Enabled": false,
				"Quantity": 0
			}
		},
		"ViewerCertificate": {
			"SSLSupportMethod": "sni-only",
			"ACMCertificateArn": "$CERT_ARN",
			"MinimumProtocolVersion": "TLSv1",
			"Certificate": "$CERT_ARN",
			"CertificateSource": "acm"
		},
		"CustomErrorResponses": {
			"Quantity": 2,
			"Items": [
				{
					"ErrorCode": 403,
					"ResponsePagePath": "/$ERROR_DOCUMENT",
					"ResponseCode": "404",
					"ErrorCachingMinTTL": 300
				},
				{
					"ErrorCode": 404,
					"ResponsePagePath": "/$ERROR_DOCUMENT",
					"ResponseCode": "404",
					"ErrorCachingMinTTL": 300
				}
			]
		},
		"Aliases": {
			"Quantity": 2,
			"Items": [
				"$DOMAIN_NAME",
				"www.$DOMAIN_NAME"
			]
		}
	}
	EOF

	aws cloudfront create-distribution --distribution-config "$CLOUDFRONT_CONFIG" 
}

configure_dns () {
	local DNS_CONFIG

	echo "Configuring DNS..."

	IFS=$'\n' read -r -d '' DNS_CONFIG <<-EOF
	{
		"Changes": [
			{
				"Action": "UPSERT",
				"ResourceRecordSet": {
					"AliasTarget": {
						"HostedZoneId": "Z2FDTNDATAQYW2",
						"EvaluateTargetHealth": false,
						"DNSName": "$CLOUDFRONT_URI"
					},
					"Type": "A",
					"Name": "$DOMAIN_NAME"
				}
			},
			{
				"Action": "UPSERT",
				"ResourceRecordSet": {
					"ResourceRecords": [
						{
							"Value": "$CLOUDFRONT_URI"
						}
					],
					"Type": "CNAME",
					"Name": "www.$DOMAIN_NAME",
					"TTL": 300
				}
			}
		]
	}
	EOF

	aws route53 change-resource-record-sets \
		--hosted-zone-id "$ZONE_ID" \
		--change-batch "$DNS_CONFIG"
}

if [ $# -eq 0 ]; then
	create_content_bucket
	configure_logging
	request_certificate
	echo "Everything has been setup for your Cloudfront distribution" \
		"and your TLS certificate has been requested from AWS. When " \
		" your certificate has been validated, re-run this" \
		"script with the argument 'continue'"
elif [ "$1" == 'continue' ]; then
	configure_cloudfront
	configure_dns
fi
