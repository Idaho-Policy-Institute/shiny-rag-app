FROM rocker/shiny:4.3.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install R packages one by one to catch errors
RUN R -e "install.packages(c('shiny', 'shinydashboard', 'shinyWidgets', 'DT', 'httr2', 'dplyr', 'stringr', 'readr', 'purrr', 'glue', 'markdown'), repos='https://cran.rstudio.com/')"
# Install ragnar separately and check if it installs
RUN R -e "install.packages('ragnar', dependencies = TRUE, repos='https://cran.rstudio.com/'); library(ragnar); cat('ragnar loaded successfully\\n')"

# Copy app files
COPY . /srv/shiny-server/
WORKDIR /srv/shiny-server/

RUN curl -L -o ipi.ragnar.duckdb "https://github.com/Idaho-Policy-Institute/shiny-rag-app/releases/download/v0.1-prototype/ipi.ragnar.duckdb"

# Expose port
EXPOSE 3838

# Run app
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]