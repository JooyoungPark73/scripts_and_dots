ulimit -n 1000000

git config --global user.name "JooYoung Park"
git config --global user.email jooyoung.park73@gmail.com

git clone https://github.com/NeHalem90/airflow.git
cd airflow

# build and name to airflow:test
docker build . -f Dockerfile --pull --no-cache --tag airflow:test
docker tag airflow:test docker.io/nehalem90/airflow:test

# install helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# deploy airflow
kubectl create namespace airflow
sudo mkdir -p /mnt/data{0..19}
sudo chmod 777 /mnt/data*
kubectl -n airflow apply -f config/volumes.yaml
helm upgrade -f config/values.yaml airflow ./chart --install --namespace airflow

# uninstall airflow
helm uninstall -n airflow airflow
kubectl delete namespace airflow
kubectl delete -f config/volumes.yaml
sudo rm -rf /mnt/data*/*