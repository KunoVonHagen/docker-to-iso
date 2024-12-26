FROM alpine:latest

RUN apk add --no-cache bash

RUN adduser -D testuser && \
    mkdir -p /home/testuser && \
    chown -R testuser:testuser /home/testuser

USER $USERNAME
WORKDIR /home/testuser

RUN echo '#!/bin/bash' > log_time.sh && \
    echo 'while true; do' >> log_time.sh && \
    echo '  date > /home/testuser/logfile.log' >> log_time.sh && \
    echo '  sleep 5' >> log_time.sh && \
    echo 'done' >> log_time.sh && \
    chmod +x log_time.sh


CMD ["bash", "-c", "/home/testuser/log_time.sh"]
