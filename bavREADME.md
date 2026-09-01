pip install -r requirements.txt
python app.py

levanta en: http://localhost:5000

## construir imagen BLUE

`docker build -t todo-app:blue .`

verificamos que exista: `docker images`

## ejecutamos el contenedor

`docker run -p 5000:5000 --name todo-blue todo-app:blue`

entramos a: http://localhost:5000

para frenarlo: `docker stop todo-blue`
para borrarlo: `docker rm todo-blue`

# pasamos la app a kubernetes

primero levantamos: `minikube start`
`kubectl get nodes`

subimos la img para q minikube la pueda ver: `minikube image load todo-app:blue`
