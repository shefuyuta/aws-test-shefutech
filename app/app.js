const express = require("express");
const { MongoClient } = require("mongodb");

const app = express();
app.use(express.json());
app.use(express.static("public"));

const mongoUrl = process.env.MONGO_URL || "mongodb://mongo:27017";

let db;

MongoClient.connect(mongoUrl).then(client => {
  db = client.db("wizdb");
  console.log("Connected to MongoDB");
});

// 投稿
app.post("/post", async (req, res) => {
  const { text } = req.body;
  await db.collection("posts").insertOne({ text, createdAt: new Date() });
  res.send("ok");
});

// 一覧取得
app.get("/posts", async (req, res) => {
  const posts = await db.collection("posts").find().toArray();
  res.json(posts);
});

app.listen(3000, () => console.log("Server running on port 3000"));