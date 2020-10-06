#!/usr/bin/env bash

DOMAIN_NAME=
REGION=
INDEX_DOCUMENT=
ERROR_DOCUMENT=
# set to any non-empty string to take effect
WILDCARD_CERT=
LOGFILE='cloudfront_configuration.log'

log() {
	if [ "$1" = "-f" ]; then
		printf '%s  %s\n' "$(date +%F\ %T)" "$@" >> "$LOGFILE"
	else
		printf '%s  %s\n' "$(date +%F\ %T)" "$@" | tee -a "$LOGFILE"
	fi
}

if [ -z "$DOMAIN_NAME" ]; then
	read -p "Domain Name [e.g. example.com]: " DOMAIN_NAME
	if [ -z "$DOMAIN_NAME" ]; then
		printf '\n%s\n' "Error: you must enter a domain name registered with or trasfered to AWS Route53 to proceed"
		exit 1
	fi
fi

if [ -z "$REGION" ]; then
	read -p "AWS Region [default: us-east-1]: " REGION
	REGION=${REGION:-us-east-1}
fi

if [ -z "$INDEX_DOCUMENT" ]; then
	read -p "Index document [default: index.html]: " INDEX_DOCUMENT
	INDEX_DOCUMENT=${INDEX_DOCUMENT:-index.html}
fi

if [ -z "$ERROR_DOCUMENT" ]; then
	read -p "Erro document [default: 404.html]: " ERROR_DOCUMENT
	ERROR_DOCUMENT=${ERROR_DOCUMENT:-404.html}
fi
if [ -z "$WILDCARD_CERT" ]; then
	read -p "Request wildcard certificate? [default: yes]: " WILDCARD_CERT
	WILDCARD_CERT=${WILDCARD_CERT:=1}
fi

echo
log "DOMAIN_NAME=$DOMAIN_NAME"
log "REGION=$REGION"
log "INDEX_DOCUMENT=$INDEX_DOCUMENT"
log "ERROR_DOCUMENT=$ERROR_DOCUMENT"
log "WILDCARD_CERT=$WILDCARD_CERT"
echo
read -p "Hit enter to continue or Ctrl+C to exit."

exit 1
configure_buckets () {
	local BUCKET_POLICY LOGGING_POLICY WEBSITE_CONFIG

	CONTENT_BUCKET="$DOMAIN_NAME"
	log -f "aws_resource: CONTENT_BUCKET=$CONTENT_BUCKET"

	LOGGING_BUCKET="${CONTENT_BUCKET}-logs"
	log -f "aws_resource: LOGGING_BUCKET=$LOGGING_BUCKET"

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

	if ! aws s3 ls "$CONTENT_BUCKET" 2>/dev/null; then
		log "Creating S3 bucket named $CONTENT_BUCKET for content to be served by Cloudfront distribution"
		API_RESPONSE="$(
			aws s3api create-bucket \
				--bucket "$CONTENT_BUCKET" \
				--region "$REGION" \
				|| log "ERROR: failed to create bucket $LOGGING_BUCKET"
		)"
		log "$API_RESPONSE"
	fi

	log "Applying the following bucket policy to bucket $CONTENT_BUCKET: $BUCKET_POLICY"
	API_RESPONSE="$(
		aws s3api put-bucket-policy \
			--bucket "$CONTENT_BUCKET" \
			--policy "$BUCKET_POLICY" \
			|| log "ERROR: failed to apply bucket policy"
	)"
	log "$API_RESPONSE"

	log "Configuring bucket $CONTENT_BUCKET to host a static website: $WEBSITE_CONFIG"
	API_RESPONSE="$(
		aws s3api put-bucket-website \
			--bucket "$CONTENT_BUCKET" \
			--website-configuration "$WEBSITE_CONFIG" \
			|| log "ERROR: configure bucket to host static website"
	)"
	log "$API_RESPONSE"

	IFS=$'\n' read -r -d '' LOGGING_POLICY <<-EOF
	{
	  "LoggingEnabled": {
		"TargetBucket": "$LOGGING_BUCKET",
		"TargetPrefix": "logs/"
		}
	}
	EOF

	if ! aws s3 ls "$LOGGING_BUCKET" 2>/dev/null; then
		log "Creating S3 bucket named $LOGGING_BUCKET for Cloudfront distribution logs"
		API_RESPONSE="$(
			aws s3api create-bucket \
				--bucket "$LOGGING_BUCKET" \
				--region "$REGION" \
				|| log "ERROR: failed to create bucket $LOGGING_BUCKET"
		)"
		log "$API_RESPONSE"
	fi

	# the put-bucket-acl command is required to grant S3's log delivery
	# system the necessary permissions (write and read-acp permissions)
	log "Granting bucket AWS LogDelivery read/write permissions to $LOGGING_BUCKET"
	API_RESPONSE="$(
		aws s3api put-bucket-acl \
			--bucket "$LOGGING_BUCKET" \
			--grant-write URI='http://acs.amazonaws.com/groups/s3/LogDelivery' \
			--grant-read-acp URI='http://acs.amazonaws.com/groups/s3/LogDelivery' \
			|| log "ERROR: failed to grant LogDelivery permissions to $LOGGING_BUCKET"
	)"
	log "$API_RESPONSE"

	log "Applying the following logging policy to bucket $CONTENT_BUCKET: $LOGGING_POLICY"
	API_RESPONSE="$(
		aws s3api put-bucket-logging \
			--bucket "$CONTENT_BUCKET" \
			--bucket-logging-status "$LOGGING_POLICY" \
			|| log "ERROR: failed to assign logging policy"
	)"
	log "$API_RESPONSE"
	log "Bucket completion and configuration complete!"
}

request_certificate () {
	local RECORD_NAME RECORD_VALUE MAKE_CNAME_RECORD
	CERT_VALIDATION_IN_PROGRESS=1

	if [ -n "$WILDCARD_CERT" ]; then
		CERT_ALT_NAME="*.$DOMAIN_NAME"
	else
		CERT_ALT_NAME="www.$DOMAIN_NAME"
	fi

	log "Requesting certificate for $DOMAIN_NAME + alternate name $CERT_ALT_NAME"
	API_RESPONSE="$(
		aws acm request-certificate \
			--domain-name "$DOMAIN_NAME" \
			--subject-alternative-names "$CERT_ALT_NAME" \
			--validation-method DNS \
			--idempotency-token "$(date +%s)" \
			|| log "ERROR: certificate request failed"
	)"
	log "$API_RESPONSE"
	CERT_ARN="$( echo "$API_RESPONSE" | jq '.CertificateArn' )"
	log -f "aws_resource: CERT_ARN=$CERT_ARN"

	RESOURCE_RECORD="$( 
		aws acm describe-certificate "$CERT_ARN" \
			| jq '.Certificate.DomainValidationOptions[] 
				| select( .DomainName | test( "'"$DOMAIN_NAME"'" )).ResourceRecord'
	)"
	RECORD_NAME="$( echo "$RESOURCE_RECORD" | jq '.Name' )" 
	RECORD_NAME="$( echo "$RESOURCE_RECORD" | jq '.Value' )" 

	ZONE_ID="$( aws route53 list-hosted-zones \
		| jq -r '.HostedZones[] | select( .Name | test("'"$DOMAIN_NAME"'")).Id' \
		| cut -d/ -f3 )"
	log -f "aws_resource: ZONE_ID=$ZONE_ID"

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
	log "Adding CNAME record to zone associated with $DOMAIN_NAME for DNS certificate validation process"
	API_RESPONSE="$(
		aws route53 change-resource-record-set "$MAKE_CNAME_RECORD" \
		|| log "ERROR: failed to add CNAME record"
	)"
	log "$API_RESPONSE"
	log "Certificate request complete!"
}

check_cert_status() {
	CERT_STATUS="$(
		aws acm describe-certificate --certificate-arn "$CERT_ARN" \
			| jq '[.Certificate.DomainValidationOptions[] 
					| {ValidationDomain: .ValidationDomain,ValidationStatus: .ValidationStatus}]' \
						|| log "ERROR: failed to check certificate DNS validation status"
	)"
	log "$(printf 'Certificate validation status:\n%s' "$CERT_STATUS")"
}

configure_cloudfront () {
	local CLOUDFRONT_CONFIG
	CLOUDFRONT_DEPLOYMENT_IN_PROGRESS=1
	
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

	log "Creating Cloudfront distribution with the following configuration: $CLOUDFRONT_CONFIG"
	API_RESPONSE="$(
		aws cloudfront create-distribution --distribution-config "$CLOUDFRONT_CONFIG" \
			|| log "ERROR: failed to create Cloudfront distribution"
	)"
	log "$API_RESPONSE"
	CLOUDFRONT_ID="$( echo "$API_RESPONSE" | jq '.Distribution.Id' )"
	log -f "aws_resource: CLOUDFRONT_ID=$CLOUDFRONT_ID"
	log "Cloudfront deployment initialized!"
}

check_cloudfront_status() {
	CLOUDFRONT_STATUS="$(
		aws cloudfront list-distributions \
			| jq '.DistributionList.Items[] | select(.Id | test( "'"$CLOUDFRONT_ID"'")).Status' \
				|| log "ERROR: failed to check Cloudfront distribution deployment status"
	)"
	log "$(printf 'Cloudfront deployment status: %s' "$CLOUDFRONT_STATUS")"
}

configure_dns () {
	local DNS_CONFIG

	IFS=$'\n' read -r -d '' DNS_CONFIG <<-EOF
	{
		"Changes": [
			{
				"Action": "UPSERT",
				"ResourceRecordSet": {
					"AliasTarget": {
						"HostedZoneId": "Z2FDTNDATAQYW2",
						"EvaluateTargetHealth": false,
						"DNSName": "$CLOUDFRONT_ID"
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
							"Value": "$CLOUDFRONT_ID"
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

	log "Adding A & CNAME records for $DOMAIN_NAME pointing to Cloudfront distribution"
	API_RESPONSE="$(
		aws route53 change-resource-record-sets \
			--hosted-zone-id "$ZONE_ID" \
			--change-batch "$DNS_CONFIG" \
			|| log "ERROR: failed to add A & CNAME records for $DOMAIN_NAME"
	)"
	log "$API_RESPONSE"
}


case "$1" in
	-h | help | --help)
		usage
		exit 0
esac

configure_buckets

request_certificate
while [ "$CERT_VALIDATION_IN_PROGRESS" ]; do
	check_if_cert_validated
	if [ "$(echo "${CERT_STATUS^^}" | grep -c 'SUCCESS')" -eq 2 ]; then
		unset CERT_VALIDATION_IN_PROGRESS
	else
		sleep 360
	fi
done

configure_cloudfront
while [ "$CLOUDFRONT_DEPLOYMENT_IN_PROGRESS" ]; do
	check_cloudfront_status
	if [ "${CLOUDFRONT_STATUS^^}" = "DEPLOYED" ]; then
		unset CLOUDFRONT_DEPLOYMENT_IN_PROGRESS
	else
		sleep 360
	fi
done

configure_dns

IFS=$'\n' read -r -d '' HUGO_DEPLOYMENT_CONFIG <<-EOF
[deployment]
	[[deployment.targets]]
	name = "S3 hosted Hugo site"
	URL = "s3://$CONTENT_BUCKET?region=$REGION"
	cloudFrontDistributionID = $CLOUDFRONT_ID
EOF

printf '%s\n%s\n\n%s' \
	"Your Cloudfront distribution has been successfully deployed!" \
	"Put this in your Hugo configuration to deploy to your new Cloudfront distribution:" \
	"$HUGO_DEPLOYMENT_CONFIG" \
	| tee -a "$LOGFILE"
