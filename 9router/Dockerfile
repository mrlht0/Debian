FROM antiantiops/9router:0.3.69

# Render sẽ dùng port này
ENV PORT=20128

# đảm bảo bind ra ngoài
EXPOSE 20128

# nếu image chưa có CMD rõ ràng thì fallback
CMD ["bun", "server.js"]
