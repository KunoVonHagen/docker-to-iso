# Use the Debian base image
FROM debian:bullseye

# Create a text file in /root with the content "hello"
RUN echo "hello" > /root/hello.txt

# Default command to keep the container running
CMD ["tail", "-f", "/dev/null"]
