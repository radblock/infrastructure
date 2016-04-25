#! /bin/bash

rm -rf repos ;

mkdir repos ;
cd repos ;

  git clone git@github.com:radblock/gimme.git ;
  cd gimme ;
    npm install ;
  cd .. ;

  git clone git@github.com:radblock/list-s3-bucket.git ;
  cd list-s3-bucket ;
    npm install ;
  cd .. ;

  git clone git@github.com:radblock/website.git ;
  cd website
    npm install ;
  cd .. ;

cd .. ;

