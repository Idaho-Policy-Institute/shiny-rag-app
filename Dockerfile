FROM rocker/shiny:latest

# Install system dependencies
RUN apt-get clean && \
    apt-get update --fix-missing && \
    apt-get update && \
    apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    curl \
    libsqlite3-dev \
    libxml2-dev \
    libmbedtls-dev \
    cmake \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Set working directory first
WORKDIR /srv/shiny-server/

# Install renv
RUN R -e "install.packages('renv', repos='https://cran.rstudio.com/')"

# Copy ALL app files (including renv files) to the working directory
COPY . .

# Set renv cache location
ENV RENV_PATHS_CACHE=/opt/renv/cache
RUN mkdir -p $RENV_PATHS_CACHE

# Restore packages from renv.lock
RUN R -e "renv::restore()"

# Copy app files
COPY . /srv/shiny-server/
WORKDIR /srv/shiny-server/

#Download database file
RUN curl -L -o ipi_noembed.ragnar.duckdb "https://github.com/Idaho-Policy-Institute/shiny-rag-app/releases/download/v0.1-prototype/ipi_noembed.ragnar.duckdb"

# Expose port
EXPOSE 3838

# Run app
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]
