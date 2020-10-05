IMG_NAME := l0xy/hugo-s3:0.1
SRC_DIR ?= $(shell pwd)/src
OUTPUT_DIR ?= $(shell pwd)/output
SITE_NAME ?= hugo-website
PORT ?= 1313

image: Dockerfile
	@docker build -t ${IMG_NAME} .

serve:
	@docker run -it --rm --name ${SITE_NAME} -v ${SRC_DIR}:/src -p ${PORT}:1313 ${IMG_NAME}

deploy:
	@docker run --rm -e "DEPLOY=1" -v ${HOME}/.aws:/root/.aws -v ${SRC_DIR}:/src ${IMG_NAME}
	@if [ -f ./site-specific-deployment.sh ]; then ./site-specific-deployment.sh; fi

.PHONY = image serve build deploy

