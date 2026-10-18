from flask import Flask, render_template, request, redirect, url_for
from flask import Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST


app = Flask(__name__)

APP_VERSION = "green"

operations = Counter(
    "todo_operations",
    "Total number of task operations",
    ["operation", "version"]
)

for action in ("create", "complete", "delete"):
    operations.labels(operation=action, version=APP_VERSION)

tasks = []
next_id = 1


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
        "index_green.html",
        tasks=filtered_tasks,
        current_filter=task_filter,
        version="GREEN v2"
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
        
        operations.labels(
            operation="create",
            version=APP_VERSION
        ).inc()
        
        next_id += 1

    return redirect(url_for("index"))


@app.route("/complete/<int:task_id>", methods=["POST"])
def complete_task(task_id):
    for task in tasks:
        if task["id"] == task_id:
            task["completed"] = not task["completed"]
            operations.labels(
                operation="complete",
                version=APP_VERSION
            ).inc()
            break

    return redirect(url_for("index"))


@app.route("/delete/<int:task_id>", methods=["POST"])
def delete_task(task_id):
    global tasks

    previous_count = len(tasks)

    tasks = [task for task in tasks if task["id"] != task_id]

    if len(tasks) < previous_count:
        operations.labels(
            operation="delete",
            version=APP_VERSION
        ).inc()

    return redirect(url_for("index"))

@app.route("/metrics")
def metrics():
    return Response(
        generate_latest(),
        headers={"Content-Type": CONTENT_TYPE_LATEST}
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)