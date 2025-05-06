#!/bin/bash

# (sleep 3 && printf "GET / HTTP/1.1\r\n\r\n") | nc localhost/user-agent 4221
# (sleep 3 && printf "GET / HTTP/1.1\r\n\r\n") | nc localhost/user-agent 4221
# (sleep 3 && printf "GET / HTTP/1.1\r\n\r\n") | nc localhost/user-agent 4221

# (sleep 0 && curl --http1.1 -v http://localhost:4221/echo/banana --next http://localhost:4221/user-agent -H "User-Agent: blueberry/apple-blueberry")
# (sleep 0 && curl --http1.1 -v http://localhost:4221/echo/banana --next http://localhost:4221/user-agent -H "User-Agent: blueberry/apple-blueberry")
# (sleep 0 && curl --http1.1 -v http://localhost:4221/echo/banana --next http://localhost:4221/user-agent -H "User-Agent: blueberry/apple-blueberry")
# (sleep 0 && curl --http1.1 -v http://localhost:4221/echo/banana --next http://localhost:4221/user-agent -H "User-Agent: blueberry/apple-blueberry")

for ((i = 0; i < 200; i++)); do
  curl --http1.1 -v http://localhost:4221/echo/banana --next http://localhost:4221/user-agent -H "User-Agent: blueberry/apple-blueberry"
done
