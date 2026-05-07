FROM nginx:alpine

# Xóa config default
RUN rm /etc/nginx/conf.d/default.conf

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy chỉ những file cần thiết (giảm image size)
COPY index.html /usr/share/nginx/html/
COPY app.html /usr/share/nginx/html/
COPY profile.html /usr/share/nginx/html/
COPY default-avatar.png /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/

RUN chmod -R 755 /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]