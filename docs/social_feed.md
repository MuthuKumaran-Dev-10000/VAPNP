# Social Feed Flow

This document details the features, image upload pathways, and real-time interaction logic of the SevaSetu Social Wall.

---

## 1. Social Feed Listing & Streams

The Social Wall tab allows Temples and Priests to post updates, and Devotees to view them.
* **Data Synced**:
  * The feed is loaded through a global realtime stream `/seva/posts` sorted descending by epoch timestamps (`timestamp`).
  * Subscribed inside `AppProvider.listenAllGlobalData()` via `_firebaseService.getPostsStream()`.

---

## 2. Cloudinary Upload for Post Media

To upload profile pictures and post images without using native `File` paths (which crash on Flutter Web), SevaSetu uses a web-safe bytes-based upload method:
* **Mechanism**:
  1. The user picks an image using `ImagePicker.pickImage(source: ImageSource.gallery)`.
  2. The image is loaded into memory as a byte list:
     `final bytes = await image.readAsBytes();`
  3. The client calls `CloudinaryService.uploadImageBytes(bytes, image.name)` to send the raw bytes directly to Cloudinary using a web-compatible HTTP multipart request:
     * **Upload Endpoint**: `https://api.cloudinary.com/v1_1/dxn2qjbcg/image/upload`
     * **Parameters**:
       * `file`: Base64 encoded or raw multipart bytes.
       * `upload_preset`: `"ml_default"` (anonymous direct upload preset).
  4. Cloudinary returns a JSON response containing the HTTPS image URL (`secure_url`), which is then saved as the post's `imageUrl` in the Firebase Realtime Database.

---

## 3. Realtime Likes Integration

Devotees can like/unlike social wall updates.
* **Sync Actions**:
  * **Path**: `/seva/likes/<postId>/<userId>`
  * **Toggle Mechanics**:
    * Checking if a user has liked a post queries the specific node:
      `FirebaseDatabase.instance.ref('seva/likes/$postId/$userId').get()`
    * If the node exists, liking again removes the node (`remove()`).
    * If the node does not exist, liking writes the value `true` under the user's ID.
  * Likes counts are dynamically fetched by counting the children of `/seva/likes/<postId>`.

---

## 4. Comment Sheets Integration

Devotees can discuss posts in real time through sliding comment sheets.
* **Sync Actions**:
  * **Path**: `/seva/comments/<postId>/<commentId>`
  * **Loading Comments**: Comment lists are retrieved using a `FutureBuilder` querying `/seva/comments/$postId`.
  * **Pushing Comments**: Submitting a comment compiles user ID, user name, text content, and timestamp, pushing it to the post's subnode in the RTDB.
