IMAGE_NAME=hashicorpdev/consul-ecs-test
VERSION=0.3.3

IMAGE_TAG=$(IMAGE_NAME):$(VERSION)

build:
	docker build -f Test.dockerfile -t $(IMAGE_TAG) .

push: build
	docker push $(IMAGE_TAG)

.PHONY: build push
