import os
import secrets

from flask import Flask, render_template, request, redirect, url_for
from flask_wtf.csrf import CSRFProtect

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY") or secrets.token_hex(32)
CSRFProtect(app)

tasks = []
next_id = 1


@app.route("/")
def index():
    return render_template(
        "index.html",
        tasks=tasks,
        version="BLUE v1"
    )


@app.route("/add", methods=["POST"])
def add_task():
    global next_id

    title = request.form.get("title")

    if title:
        task = {
            "id": next_id,
            "title": title,
            "completed": False
        }

        tasks.append(task)
        next_id += 1

    return redirect(url_for("index"))


@app.route("/complete/<int:task_id>", methods=["POST"])
def complete_task(task_id):
    for task in tasks:
        if task["id"] == task_id:
            task["completed"] = not task["completed"]
            break

    return redirect(url_for("index"))


@app.route("/delete/<int:task_id>", methods=["POST"])
def delete_task(task_id):
    global tasks

    tasks = [task for task in tasks if task["id"] != task_id]

    return redirect(url_for("index"))


if __name__ == "__main__":
    # El contenedor debe escuchar en todas sus interfaces; Docker/Kubernetes limita la exposición de red.
    # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
    app.run(host="0.0.0.0", port=5000)
