FROM perl:5.24.0
MAINTAINER  Markus Benning <ich@markusbenning.de>

COPY ./cpanfile /mtpolicyd/cpanfile
WORKDIR /mtpolicyd

RUN cpanm --notest Carton \
  && carton install \
  && rm -rf ~/.cpanm

RUN addgroup --system mtpolicyd \
  && adduser --system --home /mtpolicyd --no-create-home \
    --disabled-password --ingroup mtpolicyd mtpolicyd

COPY . /mtpolicyd
COPY ./etc/docker.conf /etc/mtpolicyd/mtpolicyd.conf

EXPOSE 12345

CMD [ "carton",  "exec", "bin/mtpolicyd", "-f", "-l", "2", "-c", "/etc/mtpolicyd/mtpolicyd.conf" ]
