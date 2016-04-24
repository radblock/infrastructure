#! /bin/bash

mkdir repos ;
cd repos ;

  git clone git@github.com:radblock/gimme.git ;
  cd gimme ;
    npm install ;
    zip -r ../uploader.zip . ;
  cd .. ;

  git clone git@github.com:radblock/list-s3-bucket.git ;
  cd list-s3-bucket ;
    npm install ;
    zip -r ../list-s3-bucket.zip . ;
  cd .. ;

  git clone git@github.com:radblock/website.git ;

cd .. ;
