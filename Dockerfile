FROM rocker/shiny:4.3.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R packages one by one to catch errors
RUN R -e "install.packages('shiny', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('shinydashboard', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('DT', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('dplyr', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('httr2', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('shinyWidgets', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('tidyverse', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('fs', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('glue', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('markdown', repos='https://cran.rstudio.com/')"
RUN R -e "install.packages('ragnar', repos='https://cran.rstudio.com/')"


# Copy app files
COPY . /srv/shiny-server/
WORKDIR /srv/shiny-server/

# Expose port
EXPOSE 3838

# Run app
CMD ["R", "-e", "shiny::runApp(host='0.0.0.0', port=3838)"]