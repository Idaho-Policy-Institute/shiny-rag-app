# Load required libraries
library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(DT)
library(httr2)
library(dplyr)
library(stringr)
library(readr)
library(purrr)
library(glue)
library(markdown)
library(ragnar)

#library(tidyverse)
#library(ragnar)
#library(ollamar)
#library(ellmer)
#library(fs)

# UI
ui <- dashboardPage(
  dashboardHeader(title = "Idaho Policy Institute AI Research Assistant"),

  dashboardSidebar(
    sidebarMenu(
      menuItem("Ask Questions", tabName = "chat", icon = icon("comments")),
      menuItem("Document Library", tabName = "library", icon = icon("book")),
      menuItem("Usage Stats", tabName = "stats", icon = icon("chart-bar"))
    )
  ),

  dashboardBody(
    tags$head(
      tags$style(HTML(
        "
        .content-wrapper, .right-side {
          background-color: #f4f4f4;
        }
        .chat-container {
          max-height: 500px;
          overflow-y: auto;
          padding: 10px;
          background: white;
          border-radius: 5px;
          margin-bottom: 15px;
        }
        .user-message {
          background: #e3f2fd;
          padding: 10px;
          margin: 5px 0;
          border-radius: 10px;
          border-left: 4px solid #2196f3;
        }
        .assistant-message {
          background: #f5f5f5;
          padding: 10px;
          margin: 5px 0;
          border-radius: 10px;
          border-left: 4px solid #4caf50;
        }
        .token-info {
          font-size: 12px;
          color: #666;
          margin-top: 5px;
        }
          .works-cited {
    background: #f9f9f9;
    border: 1px solid #ddd;
    border-radius: 5px;
    padding: 10px;
    margin-bottom: 10px;
  }
  
  .citation-item {
    background: white;
    border-left: 3px solid #337ab7;
    padding: 8px 12px;
    margin-bottom: 8px;
    border-radius: 3px;
    box-shadow: 0 1px 2px rgba(0,0,0,0.1);
  }
  
  .citation-title {
    font-weight: bold;
    color: #2c3e50;
    margin-bottom: 4px;
  }
  
  .citation-path {
    font-size: 11px;
    color: #7f8c8d;
    font-family: monospace;
  }
      "
      ))
    ),

    tabItems(
      tabItem(
        tabName = "chat",
        fluidRow(
          box(
            title = "Ask About Idaho Policy Institute research...",
            status = "primary",
            solidHeader = TRUE,
            width = 8,

            uiOutput("chat_display"),

            fluidRow(
              column(
                10,
                textAreaInput(
                  "user_question",
                  NULL,
                  placeholder = "Ask a question about Idaho Policy Institute research reports...",
                  height = "100px",
                  width = "100%"
                )
              ),
              column(
                2,
                br(),
                actionButton(
                  "submit_question",
                  "Ask",
                  class = "btn-primary",
                  style = "margin-top: 5px; height: 90px; width: 100%;"
                )
              )
            ),

            br(),

            fluidRow(
              column(
                12,
                numericInput(
                  "n_chunks",
                  "Number of document chunks:",
                  value = 5,
                  min = 1,
                  max = 10
                )
              ) #,
              # column(
              #   6,
              #   checkboxInput(
              #     "show_sources",
              #     "Show source documents",
              #     value = TRUE
              #   )
              # )
            )
          ),

          box(
            title = "Works Cited",
            status = "info",
            solidHeader = TRUE,
            width = 4,

            conditionalPanel(
              condition = "output.has_sources",
              p("Sources referenced in the most recent response:"),
              uiOutput("works_cited_display")
            ),

            conditionalPanel(
              condition = "!output.has_sources",
              p(
                "No sources available. Ask a question to see cited documents.",
                style = "color: #666; font-style: italic;"
              )
            )
          )
        )
      ),

      tabItem(
        tabName = "library",
        fluidRow(
          box(
            title = "Document Library",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            DT::dataTableOutput("document_table")
          )
        )
      ),
      tabItem(
        tabName = "stats",
        fluidRow(
          valueBoxOutput("total_questions"),
          valueBoxOutput("total_tokens"),
          valueBoxOutput("avg_response_time")
        ),
        fluidRow(
          box(
            title = "Recent Questions",
            status = "success",
            solidHeader = TRUE,
            width = 12,
            DT::dataTableOutput("question_history")
          )
        )
      )
    )
  )
)

# Server
server <- function(input, output, session) {
  values <- reactiveValues(
    store = NULL,
    files = NULL,
    chat_history = list(),
    question_count = 0,
    total_tokens = 0,
    response_times = numeric(0),
    current_sources = NULL
  )

  #file_metadata = read_csv("File_List.csv")

  process_citations <- function(sources_data, file_metadata) {
    if (is.null(sources_data) || nrow(sources_data) == 0) {
      return(NULL)
    }

    # Get unique documents from sources
    unique_docs <- sources_data %>%
      select(origin) %>%
      distinct(origin) %>%
      mutate(
        # Clean up file names
        file_name = case_when(
          str_detect(origin, "/") ~ str_extract(origin, "[^/]+$"),
          str_detect(origin, "\\\\") ~ str_extract(origin, "[^\\\\]+$"),
          TRUE ~ origin
        ),
        # Remove file extension for cleaner display
        clean_name = str_remove(file_name, "\\.(pdf|docx?|txt|md)$"),
        # Create proper title case
        display_title = str_to_title(str_replace_all(clean_name, "_", " "))
      )

    # Try to match with your existing file metadata for better titles
    if (!is.null(file_metadata) && nrow(file_metadata) > 0) {
      # If you have a file with better metadata, merge it here
      unique_docs <- unique_docs %>%
        left_join(
          file_metadata %>%
            select(file_path, file_name, authors) %>%
            rename(origin = file_path),
          by = "origin"
        ) %>%
        mutate(
          # Use metadata file name if available, otherwise use processed name
          final_title = coalesce(file_name.y, display_title)
        ) %>%
        select(origin, final_title, file_name = file_name.x, authors)
    } else {
      unique_docs <- unique_docs %>%
        mutate(final_title = display_title, authors = NA_character_)
    }

    return(unique_docs)
  }

  api_key <- Sys.getenv("CUSTOM_AI_API_KEY")

  system_prompt <- str_squish(
    "
  You are an expert assistant that summarizes policy analysis reports clearly and accurately for public users.
  When responding, you should first quote relevant material from the documents in the store,
  provide links to the sources, and then add your own context and interpretation. Try to be as concise
  as you are thorough. Documents are provided through a RAG process drawn from a collection of Idaho Policy Institute reports.
  
  For every document passed to you the output should if applicable include:
  1. Policy Summary: 1–2 paragraphs describing purpose, scope, and coverage intent.
  2. Key Points: At least 3 concise bullet points summarizing coverage criteria, limitations, exclusions, or authorization requirements.
  3. Policy Information Table in a Human-Readable HTML Format, when applicable.
  
  Model Behavior Rules:
  * If information is missing, state 'Not specified in document.'
  * Do not infer or assume; summarize only verifiable content.
  * Maintain neutral, factual tone.
  * Simplify complex report text while preserving accuracy.
  * Always follow the structure: Policy Summary → Key Points.
  * Avoid opinion, speculation, or advice; ensure clarity.
  * Format responses to be human-readable.
  "
  )

  test_api_connection <- function() {
    #NEW
    api_key <- Sys.getenv("CUSTOM_AI_API_KEY")

    if (is.null(api_key) || api_key == "") {
      return("API key not found")
    }

    tryCatch(
      {
        # Simple test request
        req <- request("https://api.boisestate.ai/chat/api-converse") |>
          req_headers(
            "Content-Type" = "application/json",
            "X-API-Key" = api_key
          ) |>
          req_body_json(list(
            modelId = "us.anthropic.claude-sonnet-4-20250514-v1:0",
            messages = list(list(
              role = "user",
              content = "Hello, this is a test."
            ))
          ))

        resp <- req_perform(req)
        return(paste("Success! Status:", resp_status(resp)))
      },
      error = function(e) {
        return(paste("API Error:", e$message))
      }
    )
  } #NEW

  initialize_rag_store <- function() {
    store_location <- "ipi_no_embed.ragnar.duckdb"

    if (!file.exists(store_location)) {
      stop("Database file not found in current directory.")
    }

    # Use isolate() to prevent reactive context issues
    #store <- isolate({
    #  ragnar_store_connect(store_location)
    #})

    store = ragnar_store_connect(store_location)

    cat("Connected to existing RAG store\n")

    files <- c("Existing documents in database")
    return(list(store = store, files = files))
  }

  observe({
    # This will run once when the app starts
    #req(is.null(values$store))
    if (!is.null(values$store)) {
      return()
    }

    showModal(modalDialog(
      title = "Connecting...",
      "Connecting to existing document database...",
      footer = NULL
    ))

    # Test API connection and show result
    api_test_result <- test_api_connection()
    cat("API Test Result:", api_test_result, "\n")
    showNotification(
      paste("API Test:", api_test_result),
      type = "warning",
      duration = 10
    )

    values$file_split_tbl <- read_csv("File_List.csv", show_col_types = FALSE)

    # Use isolate to prevent reactivity issues
    result <- tryCatch(
      {
        #isolate(initialize_rag_store())
        initialize_rag_store()
      },
      error = function(e) {
        list(error = e$message)
      }
    )

    if (!is.null(result$error)) {
      removeModal()
      showModal(modalDialog(
        title = "Connection Error",
        paste("Failed to connect to database:", result$error),
        easyClose = TRUE,
        footer = modalButton("OK")
      ))
    } else {
      values$store <- result$store
      values$files <- result$files
      removeModal()

      showNotification(
        "Successfully connected to document database!",
        type = "message",
        duration = 3
      )
    }
  })

  custom_anthropic_chat <- function(message, model, base_url, api_key) {
    req <- request(base_url) |>
      req_headers(
        "Content-Type" = "application/json",
        "X-API-Key" = api_key,
        "User-Agent" = "Mozilla/5.0 (compatible; ShinyApp)", #NEW
        "Accept" = "application/json" #NEW
      ) |>
      req_body_json(list(
        modelId = model,
        messages = list(list(
          role = "user",
          content = message
        ))
      )) |>
      req_error(body = function(resp) {
        body_text <- resp_body_string(resp)
        paste0("API Error: ", body_text)
      })

    resp <- req_perform(req)
    return(resp_body_json(resp))
  }

  custom_rag_chat <- function(
    query,
    store,
    system_prompt = "",
    n_chunks = 5
  ) {
    # Add debug output
    cat("Starting retrieval for query:", query, "\n")
    cat("Store object exists:", !is.null(store), "\n")
    cat("Store class:", class(store), "\n")

    # Try the retrieval first, with error handling
    retrieved_chunks <- tryCatch(
      {
        cat("Attempting ragnar_retrieve_vss...\n")
        #query = "TEST" #REMOVE THIS
        result <- ragnar_retrieve_vss(store, query = query, top_k = n_chunks)
        cat("Retrieval successful! Got", nrow(result), "chunks\n")
        cat("Column names:", paste(names(result), collapse = ", "), "\n")
        result
      },
      error = function(e) {
        cat("Ragnar retrieve error:", e$message, "\n")
        cat("Error class:", class(e), "\n")
        # Return empty result if retrieval fails
        data.frame(
          text = paste("Retrieval failed:", e$message),
          origin = "system",
          stringsAsFactors = FALSE
        )
      }
    )

    # Check if we got valid results
    if (nrow(retrieved_chunks) == 0 || is.null(retrieved_chunks$text)) {
      cat("No valid chunks retrieved\n")
      return(list(
        answer = "**[No Documents Found]**\n\nNo relevant documents could be found for your query. Please try rephrasing your question or using different keywords.",
        context = NULL,
        tokens_used = list(inputTokens = 0, outputTokens = 0)
      ))
    }

    context_text <- retrieved_chunks |>
      dplyr::pull(text) |>
      paste(collapse = "\n\n---\n\n")

    cat("Context text length:", nchar(context_text), "\n")

    full_message <- paste(
      system_prompt,
      "\n\n## Relevant Document Excerpts:\n",
      context_text,
      "\n\n## User Query:\n",
      query
    )

    # Add debug output
    cat("Full message length:", nchar(full_message), "\n")
    cat("First 200 chars:", substr(full_message, 1, 200), "\n")

    # Try API call with fallback
    tryCatch(
      {
        response <- custom_anthropic_chat(
          message = full_message,
          model = "us.anthropic.claude-sonnet-4-20250514-v1:0",
          base_url = "https://api.boisestate.ai/chat/api-converse",
          api_key = api_key
        )

        return(list(
          answer = response$text,
          context = retrieved_chunks,
          tokens_used = response$usage
        ))
      },
      error = function(e) {
        # Log the detailed error
        cat("Detailed API Error:", e$message, "\n")
        cat("Error class:", class(e), "\n")

        # Network blocked - return context only
        fallback_answer <- paste0(
          "**[API Error: ",
          e$message,
          "]**\n\n",
          "Here's the relevant content I found:\n\n",
          "---\n\n",
          context_text,
          "\n\n---\n\n",
          "**Your Query:** ",
          query
        )

        return(list(
          answer = fallback_answer,
          context = retrieved_chunks,
          tokens_used = list(inputTokens = 0, outputTokens = 0)
        ))
      }
    )
  }

  observeEvent(input$submit_question, {
    req(input$user_question, values$store)

    if (nchar(trimws(input$user_question)) == 0) {
      return()
    }

    # Validate n_chunks input - THIS IS THE KEY FIX
    n_chunks_value <- input$n_chunks
    if (
      is.null(n_chunks_value) || is.na(n_chunks_value) || n_chunks_value <= 0
    ) {
      n_chunks_value <- 5 # Use default
    }

    question <- trimws(input$user_question)
    start_time <- Sys.time()

    values$chat_history <- append(
      values$chat_history,
      list(list(
        type = "user",
        content = question,
        timestamp = Sys.time()
      ))
    )

    values$chat_history <- append(
      values$chat_history,
      list(list(
        type = "loading",
        content = "Processing your question...",
        timestamp = Sys.time()
      ))
    )

    updateTextAreaInput(session, "user_question", value = "")

    tryCatch(
      {
        # Always try to get result, with comprehensive error handling
        result <- tryCatch(
          {
            custom_rag_chat(
              query = question,
              store = values$store,
              system_prompt = system_prompt,
              n_chunks = n_chunks_value
            )
          },
          error = function(e) {
            # If everything fails, create a minimal fallback
            list(
              answer = paste0(
                "**[Connection Error]**\n\n",
                "Unable to process your question due to network restrictions. ",
                "The app requires external API access that isn't available on this platform.\n\n",
                "**Your question was:** ",
                question
              ),
              context = NULL,
              tokens_used = list(inputTokens = 0, outputTokens = 0)
            )
          }
        )

        end_time <- Sys.time()
        response_time <- as.numeric(difftime(
          end_time,
          start_time,
          units = "secs"
        ))

        values$chat_history <- values$chat_history[-length(values$chat_history)]

        # UPDATED: Store current sources for Works Cited
        values$current_sources <- if (!is.null(result$context)) {
          process_citations(result$context, values$file_split_tbl) # Use your file metadata
        } else {
          NULL
        }

        values$chat_history <- append(
          values$chat_history,
          list(list(
            type = "assistant",
            content = result$answer,
            timestamp = end_time,
            tokens_used = result$tokens_used,
            sources = result$context,
            response_time = response_time
          ))
        )

        values$question_count <- values$question_count + 1
        values$total_tokens <- values$total_tokens +
          result$tokens_used$inputTokens +
          result$tokens_used$outputTokens
        values$response_times <- c(values$response_times, response_time)
      },
      error = function(e) {
        values$chat_history <- values$chat_history[-length(values$chat_history)]
        values$current_sources = NULL
        values$chat_history <- append(
          values$chat_history,
          list(list(
            type = "assistant",
            content = paste("Error:", e$message),
            timestamp = Sys.time(),
            tokens_used = list(inputTokens = 0, outputTokens = 0),
            response_time = 0
          ))
        )
      }
    )
  })

  output$chat_display <- renderUI({
    chat_elements <- lapply(values$chat_history, function(msg) {
      if (msg$type == "user") {
        div(
          class = "user-message",
          strong("You: "),
          msg$content,
          div(class = "token-info", format(msg$timestamp, "%H:%M:%S"))
        )
      } else if (msg$type == "loading") {
        div(
          class = "assistant-message",
          icon("spinner fa-spin"),
          " ",
          msg$content
        )
      } else if (msg$type == "assistant") {
        source_info <- if (!is.null(msg$sources) && nrow(msg$sources) > 0) {
          paste("Sources:", nrow(msg$sources), "document chunks")
        } else {
          ""
        }

        div(
          class = "assistant-message",
          strong("Assistant: "),
          div(HTML(renderMarkdown(text = msg$content))),
          div(
            class = "token-info",
            paste(
              "Tokens:",
              msg$tokens_used$inputTokens,
              "/",
              msg$tokens_used$outputTokens
            ),
            " | Response time:",
            round(msg$response_time, 1),
            "sec",
            if (source_info != "") paste(" |", source_info) else ""
          )
        )
      }
    })

    div(
      id = "chat-display",
      class = "chat-container",
      do.call(tagList, chat_elements)
    )
  })

  # Add output for Works Cited display
  output$works_cited_display <- renderUI({
    if (is.null(values$current_sources) || nrow(values$current_sources) == 0) {
      return(NULL)
    }

    citations <- lapply(1:nrow(values$current_sources), function(i) {
      source_info <- values$current_sources[i, ]

      div(
        class = "citation-item",
        div(class = "citation-title", source_info$final_title),
        div(class = "authors", source_info$authors),
        div(
          class = "citation-path",
          paste("Source:", basename(source_info$origin))
        )
      )
    })

    div(class = "works-cited", do.call(tagList, citations))
  })

  # Add output to control conditional panel
  output$has_sources <- reactive({
    !is.null(values$current_sources) && nrow(values$current_sources) > 0
  })
  outputOptions(output, "has_sources", suspendWhenHidden = FALSE)

  output$document_table <- DT::renderDataTable({
    req(values$file_split_tbl)

    df = values$file_split_tbl

    display_df <- df %>%
      select(
        `File Name` = file_name,
        `Authors` = authors,
        `Date` = file_date
      )
    #`File Path` = file_path,
    #`Extension` = file_extension,
    #`Size` = file_size,

    DT::datatable(
      display_df,
      options = list(
        pageLength = 25,
        scrollX = TRUE,
        order = list(list(0, 'asc'))
      ),
      rownames = FALSE,
      selection = 'single'
    )
  })

  output$total_questions <- renderValueBox({
    valueBox(
      value = values$question_count,
      subtitle = "Questions Asked",
      icon = icon("question-circle"),
      color = "blue"
    )
  })

  output$total_tokens <- renderValueBox({
    valueBox(
      value = format(values$total_tokens, big.mark = ","),
      subtitle = "Total Tokens Used",
      icon = icon("coins"),
      color = "yellow"
    )
  })

  output$avg_response_time <- renderValueBox({
    avg_time <- if (length(values$response_times) > 0) {
      round(mean(values$response_times), 1)
    } else {
      0
    }

    valueBox(
      value = paste(avg_time, "sec"),
      subtitle = "Avg Response Time",
      icon = icon("clock"),
      color = "green"
    )
  })

  output$question_history <- DT::renderDataTable({
    if (length(values$chat_history) == 0) {
      return(data.frame(
        Question = character(),
        Timestamp = character(),
        stringsAsFactors = FALSE
      ))
    }

    user_messages <- values$chat_history[sapply(
      values$chat_history,
      function(x) x$type == "user"
    )]

    if (length(user_messages) == 0) {
      return(data.frame(
        Question = character(),
        Timestamp = character(),
        stringsAsFactors = FALSE
      ))
    }

    history_df <- map_dfr(user_messages, function(msg) {
      data.frame(
        Question = msg$content,
        Timestamp = format(msg$timestamp, "%Y-%m-%d %H:%M:%S"),
        stringsAsFactors = FALSE
      )
    })

    DT::datatable(
      history_df,
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        order = list(list(1, 'desc'))
      )
    )
  })
}

shinyApp(ui = ui, server = server)
