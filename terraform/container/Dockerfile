ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN pip install --no-cache-dir awscli

COPY entrypoint.sh /opt/entrypoint.sh
RUN sed -i 's/\r$//' /opt/entrypoint.sh && chmod +x /opt/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/opt/entrypoint.sh"]
