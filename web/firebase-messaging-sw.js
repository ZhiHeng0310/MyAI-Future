importScripts('https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAGfu6muyvZQxiD-i3FBcnVzi62UPijBSE",
  authDomain: "careloop-b2ec8.firebaseapp.com",
  projectId: "careloop-b2ec8,
  messagingSenderId: "362769739395",
  appId: "1:362769739395:web:44cf4c44059886e25df5b6"
});

const messaging = firebase.messaging();