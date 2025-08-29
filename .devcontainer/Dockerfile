ARG SPARK_IMAGE=raizenanalyticsdev.azurecr.io/sparkzen:3.0.0
# Antes de dar build no container, execute:
#   docker login raizenanalyticsdev.azurecr.io
FROM ${SPARK_IMAGE}

# Instalações como root
USER root
WORKDIR /app

RUN apt-get update && apt-get install -y \
        curl \
        python3 \
        python3-pip \
        python3-ipykernel \
        git \
        fzf \
    && pip3 install --upgrade pip \
    && pip3 install --no-cache-dir notebook jupyterlab \
#     && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
#     && curl https://packages.microsoft.com/config/ubuntu/18.04/prod.list \
#          > /etc/apt/sources.list.d/mssql-release.list \
#     && apt-get update \
#     && ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev \
    && chmod -R 777 /opt

USER airflow