importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAGfu6muyvZQxiD-i3FBcnVzi62UPijBSE",
  authDomain: "careloop-b2ec8.firebaseapp.com",
  projectId: "careloop-b2ec8",
  messagingSenderId: "362769739395",
  appId: "1:362769739395:web:44cf4c44059886e25df5b6"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('🔔 Background message:', payload);

  const title =
    payload.notification?.title ||
    payload.data?.title ||
    "CareLoop";

  const body =
    payload.notification?.body ||
    payload.data?.body ||
    "You have a new notification";

  self.registration.showNotification(title, {
    body: body,
    icon: '/icons/Icon-192.png'
  });
});