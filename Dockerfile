###############################################################################
### Front end                                                               ###
###############################################################################

FROM node:current AS frontend

WORKDIR /usr/src/paperless/src-ui/

COPY src-ui/package* ./
RUN npm install

COPY src-ui .
RUN node_modules/.bin/ng build --prod --output-hashing none --sourceMap=false

###############################################################################
### Back end                                                                ###
###############################################################################

FROM python:3.8-slim

WORKDIR /usr/src/paperless/

COPY Pipfile* ./

#Dependencies
RUN apt-get update \
  && apt-get -y --no-install-recommends install \
		anacron \
		build-essential \
		curl \
		ghostscript \
		gnupg \
		imagemagick \
		libmagic-dev \
		libpoppler-cpp-dev \
		libpq-dev \
		optipng \
		sudo \
		tesseract-ocr \
		tesseract-ocr-eng \
		tesseract-ocr-deu \
		tesseract-ocr-fra \
		tesseract-ocr-ita \
		tesseract-ocr-spa \
		tzdata \
		unpaper \
	&& pip install --upgrade pipenv supervisor \
	&& pipenv install --system --deploy \
	&& pipenv --clear \
	&& apt-get -y purge build-essential \
	&& apt-get -y autoremove --purge \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir /var/log/supervisord /var/run/supervisord

# copy scripts
# this fixes issues with imagemagick and PDF
COPY scripts/imagemagick-policy.xml /etc/ImageMagick-6/policy.xml
COPY scripts/gunicorn.conf.py ./
COPY scripts/supervisord.conf /etc/supervisord.conf
COPY scripts/paperless-cron /etc/cron.daily/
COPY scripts/docker-entrypoint.sh /sbin/docker-entrypoint.sh

# copy app
COPY src/ ./src/
COPY --from=frontend /usr/src/paperless/src-ui/dist/paperless-ui/ ./src/documents/static/

# add users, setup scripts
RUN addgroup --gid 1000 paperless \
	&& useradd --uid 1000 --gid paperless --home-dir /usr/src/paperless paperless \
	&& chown -R paperless:paperless . \
	&& chmod 755 /sbin/docker-entrypoint.sh \
	&& chmod +x /etc/cron.daily/paperless-cron \
	&& rm /etc/cron.daily/apt-compat /etc/cron.daily/dpkg

WORKDIR /usr/src/paperless/src/

RUN sudo -HEu paperless python3 manage.py collectstatic --clear --no-input

VOLUME ["/usr/src/paperless/data", "/usr/src/paperless/consume", "/usr/src/paperless/export"]
ENTRYPOINT ["/sbin/docker-entrypoint.sh"]
CMD ["python3", "manage.py", "--help"]
