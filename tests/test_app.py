"""Tests de la aplicación Flask (se ejecutan en la etapa "Build & Test" de Jenkins)."""
import pytest

import app as app_module
import monitor_client


@pytest.fixture
def client(monkeypatch):
    """Cliente de prueba con la lista de tareas vacía y CSRF desactivado.

    CSRF se desactiva para poder hacer POST sin token desde los tests;
    hay un test aparte (test_csrf_rechaza_post_sin_token) que verifica que
    en funcionamiento normal sí está activo.
    """
    app_module.app.config["TESTING"] = True
    app_module.app.config["WTF_CSRF_ENABLED"] = False
    monkeypatch.setattr(app_module, "tasks", [])
    monkeypatch.setattr(app_module, "next_id", 1)
    with app_module.app.test_client() as test_client:
        yield test_client
    app_module.app.config["WTF_CSRF_ENABLED"] = True


def test_index_responde_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_index_muestra_version(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "9.9.9 (test)")
    response = client.get("/")
    assert b"9.9.9 (test)" in response.data


def test_agregar_tarea(client):
    response = client.post("/add", data={"title": "Estudiar DevOps", "priority": "alta"})
    assert response.status_code == 302
    assert len(app_module.tasks) == 1
    assert app_module.tasks[0]["title"] == "Estudiar DevOps"
    assert app_module.tasks[0]["priority"] == "alta"
    assert app_module.tasks[0]["completed"] is False


def test_no_agrega_tarea_sin_titulo(client):
    client.post("/add", data={"title": ""})
    assert app_module.tasks == []


def test_completar_tarea(client):
    client.post("/add", data={"title": "Tarea"})
    client.post("/complete/1")
    assert app_module.tasks[0]["completed"] is True
    # Completar de nuevo la vuelve a pendiente
    client.post("/complete/1")
    assert app_module.tasks[0]["completed"] is False


def test_eliminar_tarea(client):
    client.post("/add", data={"title": "Tarea"})
    client.post("/delete/1")
    assert app_module.tasks == []


def test_filtros(client):
    client.post("/add", data={"title": "tarea-alfa"})
    client.post("/add", data={"title": "tarea-beta"})
    client.post("/complete/2")

    pendientes = client.get("/?filter=pending").data
    completadas = client.get("/?filter=completed").data

    assert b"tarea-alfa" in pendientes and b"tarea-beta" not in pendientes
    assert b"tarea-beta" in completadas and b"tarea-alfa" not in completadas


def test_notifica_al_monitor(client, monkeypatch):
    llamadas = []
    monkeypatch.setattr(app_module, "notify", lambda op, prio="none": llamadas.append((op, prio)))

    client.post("/add", data={"title": "Tarea", "priority": "baja"})
    client.post("/complete/1")
    client.post("/delete/1")

    assert llamadas == [("create", "baja"), ("complete", "baja"), ("delete", "baja")]


def test_monitor_caido_no_rompe_la_app(monkeypatch):
    # Puerto donde no escucha nadie: notify no debe lanzar excepciones
    monkeypatch.setattr(monitor_client, "MONITOR_URL", "http://127.0.0.1:9/api/operations")
    monitor_client.notify("create", "media")


def test_csrf_rechaza_post_sin_token():
    app_module.app.config["WTF_CSRF_ENABLED"] = True
    with app_module.app.test_client() as test_client:
        response = test_client.post("/add", data={"title": "Ataque CSRF"})
    assert response.status_code == 400
