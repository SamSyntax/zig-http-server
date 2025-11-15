# Zig HTTP Server

A simple, multithreaded HTTP server written from scratch in Zig.

This project is an educational exercise to build a functional HTTP/1.1 server, handling multiple concurrent connections and implementing several common endpoints.

## How it Works

The server listens for TCP connections on `127.0.0.1:4221`. It uses a thread pool to handle each incoming connection concurrently.

The server can parse HTTP requests, including headers and body, and generate appropriate HTTP responses. It supports GET and POST methods, keep-alive connections, and gzip compression for responses.

## Features

-   **Multithreaded:** Handles multiple clients concurrently using a thread pool.
-   **HTTP/1.1 Parsing:** Parses request lines, headers, and bodies.
-   **Endpoint Routing:** Supports the following endpoints:
    -   `GET /`: Returns a simple 200 OK response.
    -   `GET /echo/{message}`: Echoes the message back in the response body.
    -   `GET /user-agent`: Returns the client's User-Agent header in the response body.
    -   `GET /files/{filename}`: Serves a file from a specified directory.
    -   `POST /files/{filename}`: Creates a new file in a specified directory with the content of the request body.
-   **File Serving:** Can serve static files and create new files in a directory provided via a command-line argument.
-   **Gzip Compression:** Compresses response bodies if the client supports it (`Accept-Encoding: gzip`).

## How to Build and Run

You need to have Zig installed to build and run this project.

1.  **Build the server:**

    ```sh
    zig build
    ```

2.  **Run the server:**

    The server requires a directory to be specified for file-related endpoints. You can provide it using the `--directory` flag.

    ```sh
    ./zig-out/bin/zig --directory <path/to/your/directory>
    ```

    For example, to use the current directory:

    ```sh
    ./zig-out/bin/zig --directory .
    ```

    Alternatively, you can use the provided `Makefile` for a convenient shortcut:

    ```sh
    make run
    ```

    This will build the project and run the server, using the project's root as the file directory.

## How to Test

You can use a tool like `curl` to test the server's endpoints. Make sure the server is running in a separate terminal.

**Test the root endpoint:**

```sh
curl -v http://127.0.0.1:4221/
```

**Test the echo endpoint:**

```sh
curl -v http://127.0.0.1:4221/echo/hello
```

**Test the user-agent endpoint:**

```sh
curl -v -A "My-Test-Client" http://127.0.0.1:4221/user-agent
```

**Test file creation (POST):**

This command will create a file named `test.txt` in the directory you specified when running the server.

```sh
echo "Hello from a file!" | curl -v --data-binary @- http://127.0.0.1:4221/files/test.txt
```

**Test file retrieval (GET):**

This command will retrieve the content of `test.txt`.

```sh
curl -v http://127.0.0.1:4221/files/test.txt
```

**Test gzip compression:**

```sh
curl -v --compressed http://127.0.0.1:4221/echo/some-long-string-to-compress
```