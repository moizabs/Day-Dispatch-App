# Laravel authentication bridge

The DayDispatch app is a WebView shell, so Laravel owns login, logout, and the
Sanctum bearer token. The page must notify the native shell at those two
lifecycle points. The bridge is available only inside the mobile app.

## After login

Call this after Laravel has issued the user's Sanctum token:

```js
if (window.dayDispatchNative) {
    window.dayDispatchNative.login(sanctumToken, window.location.origin);
}
```

If page code loads before the native bridge, listen for its ready event:

```js
window.addEventListener('daydispatch:native-ready', () => {
    window.dayDispatchNative.login(sanctumToken, window.location.origin);
}, { once: true });
```

The app emits `daydispatch:fcm-registration` with
`event.detail.success === true` when registration succeeds. A failure must not
block Laravel login.

## Before logout

Ask the app to remove the FCM token before Laravel deletes the local Sanctum
token:

```js
async function logoutFromDayDispatch() {
    if (!window.dayDispatchNative) {
        return performLaravelLogout();
    }

    window.addEventListener('daydispatch:fcm-logout-complete', () => {
        performLaravelLogout();
    }, { once: true });

    window.dayDispatchNative.logout();
}
```

`performLaravelLogout()` should call the existing Laravel logout flow and then
remove its local token. The app always emits the completion event, including
when Firebase permission is unavailable or the DELETE request fails, so logout
cannot become stuck.

## API base URL

The bridge defaults to the currently loaded website origin. For an Android
emulator talking to a local Laravel server, load the site through
`http://10.0.2.2:<port>`. A physical phone must use the development computer's
LAN address (for example `http://192.168.1.20:<port>`) or a deployed HTTPS URL;
it cannot use `localhost` to reach the computer.

## Notification destinations

Chat notification data:

```json
{
  "type": "chat_notification",
  "chat_url": "/chat/6496",
  "sender_id": "6496",
  "chat_id": "123",
  "notification_id": "456"
}
```

Order notification data:

```json
{
  "type": "order_notification",
  "order_id": "6496",
  "order_url": "/global-search?search_criteria=8&search_query=6496"
}
```

`chat_url` and `order_url` must be relative paths beginning with one `/`.
Absolute and protocol-relative URLs are rejected. Send data-only FCM messages
when the native service must create the notification in every app state; an
FCM `notification` block may be included for title and body, but navigation is
always read from the data payload.
