# Use official Nginx Alpine image
FROM nginx:alpine

# Set working directory inside container
WORKDIR /usr/share/nginx/html

# Remove default static files
RUN rm -rf ./*

# Copy website files into container
COPY . .

# Expose port 80
EXPOSE 80

# Start Nginx in foreground
CMD ["nginx", "-g", "daemon off;"]

