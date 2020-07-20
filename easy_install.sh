#!/bin/bash

echo "Installing/upgrading workon"
mkdir -p ~/.workon
cd ~/.workon

echo " * Download the latest release"
curl -o workon.tar.gz -L https://github.com/MedicineYeh/workon/archive/v2.0.2.tar.gz
tar --strip-components=1 -xf workon.tar.gz
rm -f workon.tar.gz

echo " * Patch [bash|zsh]rc files"
[[ -f ~/.bashrc ]] && [[ "$(grep "$(pwd)/env.sh" ~/.bashrc)" == "" ]] && echo "source $(pwd)/env.sh" >> ~/.bashrc
[[ -f ~/.zshrc ]] && [[ "$(grep "$(pwd)/env.sh" ~/.zshrc)" == "" ]] && echo "source $(pwd)/env.sh" >> ~/.zshrc

echo "Done"
echo "Please reopen the console to enjoy the new command - workon"
