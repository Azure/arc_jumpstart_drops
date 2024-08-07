  cd ..
  cd ..

  # Removing any previous version of go
  sudo apt-get remove golang-go
  sudo apt remove --autoremove golang
  sudo rm -rvf /usr/loca/go/
  sudo rm -rf /usr/local/go
  sudo rm -r go

  # Update environment
  sudo apt update
  sudo apt full-upgrade
  sudo apt install make
  sudo apt update

  # Installing Go
  sudo wget https://dl.google.com/go/go1.17.linux-amd64.tar.gz
  sudo tar -xvf go1.17.linux-amd64.tar.gz
  sudo mv go /usr/local

  # setting up Go environment
  export GOROOT=/usr/local/go
  export GOPATH=$HOME/Projects/Proj1
  export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

  go version

  go install github.com/rakyll/statik@latest

  sudo apt update