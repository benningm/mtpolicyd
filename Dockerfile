FROM perl:5.24.0
MAINTAINER  Markus Benning <ich@markusbenning.de>
ENV PERL_CARTON_PATH /usr/local/lib/carton

COPY ./cpanfile /mtpolicyd/cpanfile
WORKDIR /mtpolicyd

RUN cpanm --notest Carton \
  && carton install \
  && rm -rf ~/.cpanm

RUN cpanm --notest DBD::mysql \
  && rm -rf ~/.cpanm

RUN addgroup --system mtpolicyd \
  && adduser --system --home /mtpolicyd --no-create-home \
    --disabled-password --ingroup mtpolicyd mtpolicyd

COPY . /mtpolicyd
COPY ./etc/docker.conf /etc/mtpolicyd/mtpolicyd.conf

EXPOSE 12345

USER mtpolicyd

CMD [ "carton",  "exec", "perl", "-Mlib=./lib", "bin/mtpolicyd", "-f", "-c", "/etc/mtpolicyd/mtpolicyd.conf" ]
