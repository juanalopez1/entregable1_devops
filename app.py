import os
import secrets
import time

from flask import Flask, Response, g, render_template, request, redirect, url_for
from flask_wtf.csrf import CSRFProtect
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

from monitor_client import notify

app = Flask(__name__)
# En Kubernetes la clave viene de un Secret (igual en todas las réplicas).
# Si no está definida (por ejemplo, en local), se genera una al azar.
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY") or secrets.token_hex(32)
CSRFProtect(app)

tasks = []
next_id = 1

# ============================================================
# Métricas para Prometheus (se exponen en /metrics)
# ============================================================

# Técnicas: cantidad de peticiones (RPS) y cuánto tardan (latencia)
HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Peticiones HTTP procesadas por la aplicación",
    ["method", "endpoint", "status"],
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Tiempo de respuesta de las peticiones HTTP",
    ["method", "endpoint"],
)

# De negocio: tareas creadas por prioridad y tareas actuales por estado
TASKS_CREATED = Counter(
    "todo_tasks_created_total",
    "Tareas creadas",
    ["priority"],
)
TASKS_CURRENT = Gauge(
    "todo_tasks",
    "Tareas que hay en este momento, por estado",
    ["state"],
)

PRIORITIES = {"baja", "media", "alta"}

# Endpoints que no se miden, para que Prometheus y las probes de Kubernetes
# no inflen las métricas de tráfico real
NOT_MEASURED = {"/metrics", "/healthz"}


@app.before_request
def start_timer():
    g.start_time = time.perf_counter()


@app.after_request
def record_metrics(response):
    # Se usa la ruta "plantilla" (/complete/<int:task_id>) y no la URL real,
    # para no crear una serie de métricas distinta por cada id de tarea
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"

    if endpoint not in NOT_MEASURED:
        HTTP_REQUESTS.labels(request.method, endpoint, str(response.status_code)).inc()
        if "start_time" in g:
            HTTP_LATENCY.labels(request.method, endpoint).observe(time.perf_counter() - g.start_time)

    return response


@app.route("/metrics")
def metrics():
    TASKS_CURRENT.labels("pending").set(sum(1 for task in tasks if not task["completed"]))
    TASKS_CURRENT.labels("completed").set(sum(1 for task in tasks if task["completed"]))
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.route("/healthz")
def healthz():
    # Lo usan las probes de Kubernetes (liveness y readiness)
    return {"status": "ok"}


# ============================================================
# Aplicación
# ============================================================

@app.route("/")
def index():
    task_filter = request.args.get("filter", "all")

    if task_filter == "pending":
        filtered_tasks = [task for task in tasks if not task["completed"]]
    elif task_filter == "completed":
        filtered_tasks = [task for task in tasks if task["completed"]]
    else:
        filtered_tasks = tasks

    return render_template(
        "index.html",
        tasks=filtered_tasks,
        current_filter=task_filter,
        version=os.environ.get("APP_VERSION", "v2")
    )


@app.route("/add", methods=["POST"])
def add_task():
    global next_id

    title = request.form.get("title")
    priority = request.form.get("priority", "media")

    if title:
        task = {
            "id": next_id,
            "title": title,
            "priority": priority,
            "completed": False
        }

        tasks.append(task)
        next_id += 1
        TASKS_CREATED.labels(priority if priority in PRIORITIES else "otra").inc()
        notify("create", priority)

    return redirect(url_for("index"))


@app.route("/complete/<int:task_id>", methods=["POST"])
def complete_task(task_id):
    for task in tasks:
        if task["id"] == task_id:
            task["completed"] = not task["completed"]
            notify("complete", task.get("priority", "none"))
            break

    return redirect(url_for("index"))


@app.route("/delete/<int:task_id>", methods=["POST"])
def delete_task(task_id):
    global tasks

    deleted = next((task for task in tasks if task["id"] == task_id), None)
    tasks = [task for task in tasks if task["id"] != task_id]

    if deleted:
        notify("delete", deleted.get("priority", "none"))

    return redirect(url_for("index"))


if __name__ == "__main__":
    # El contenedor debe escuchar en todas sus interfaces; Docker/Kubernetes limita la exposición de red.
    # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
    app.run(host="0.0.0.0", port=5000)
