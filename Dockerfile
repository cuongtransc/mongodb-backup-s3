FROM mongo:3.4

RUN apt-get update
RUN apt-get install -y --no-install-recommends cron awscli

ENV CRON_TIME="0 3 * * *" \
  TZ=Asia/Ho_Chi_Minh \
  CRON_TZ=Asia/Ho_Chi_Minh

COPY ./docker-entrypoint.sh /

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["CRON"]