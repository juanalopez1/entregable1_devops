from flask import Flask, render_template, request, redirect, url_for
from flask import Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

APP_VERSION = "blue"

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