.PHONY: all

all:
	docker build --progress=plain -t antage/apache2-php7:7.0 .
