#! /bin/bash

cd repos/uploader ;
npm install ;
zip -r ../uploader.zip . ;
cd ../.. ;

cd repos/list-s3-bucket ;
npm install ;
zip -r ../list-s3-bucket.zip . ;
cd ../.. ;
