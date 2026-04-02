FROM rocker/shiny:4.3.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev

# Install R packages
RUN R -e "install.packages(c('shiny', 'shinydashboard', 'DT', 'dplyr', 'httr2', 'ragnar', 'shinyWidgets', 'tidyverse', 'fs', 'glue', 'markdown'))"

# Copy app files
COPY . /srv/shiny-server/
WORKDIR /srv/shiny-server/

# Expose port
EXPOSE 3838

# Run app
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]