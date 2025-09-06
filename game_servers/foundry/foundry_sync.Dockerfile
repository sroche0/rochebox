FROM alpine:latest

RUN apk update
RUN apk add rclone
RUN echo '* * * * * rclone sync --create-empty-src-dirs dropbox:DnD/Foundry /data/' >> /etc/crontabs/root
CMD ["/usr/sbin/crond", "-f"]
