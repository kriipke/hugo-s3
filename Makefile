IMG_NAME := l0xy/hugo-s3:0.1
SRC_DIR ?= $(shell pwd)/src
OUTPUT_DIR ?= $(shell pwd)/output
SITE_NAME ?= hugo-website

image: Dockerfile
	@docker build -t ${IMG_NAME} .

serve:
	@docker run -it --rm --name ${SITE_NAME} -v ${SRC_DIR}:/src -p 1313:1313 ${IMG_NAME}

deploy:
	@docker run --rm -e "DEPLOY=1" -v ${HOME}/.aws:/root/.aws -v ${SRC_DIR}:/src ${IMG_NAME}

.PHONY = image serve build deploy

