from flask import Flask, Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import socket

app = Flask(__name__)

# HTTP 요청 횟수를 저장하는 Prometheus Counter
REQUEST_COUNT = Counter(
    'flask_http_requests_total',
    'Total number of HTTP requests',
    ['method', 'endpoint']
)

@app.before_request
def before_request():
    from flask import request

    # /metrics 자체 요청은 카운트에서 제외
    if request.path != "/metrics":
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.path
        ).inc()

@app.route("/")
def home():
    return f"""
    <h1>EKS Portfolio App</h1>
    <p>Pod Hostname: {socket.gethostname()}</p>
    """

@app.route("/health")
def health():
    return "ok", 200

@app.route("/metrics")
def metrics():
    return Response(
        generate_latest(),
        mimetype=CONTENT_TYPE_LATEST
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
