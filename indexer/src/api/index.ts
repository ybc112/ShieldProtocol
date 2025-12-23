import { db } from "ponder:api";
import schema from "ponder:schema";
import { Hono } from "hono";
import { graphql } from "ponder";

const app = new Hono();

// Enable GraphQL API at / and /graphql
app.use("/", graphql({ db, schema }));
app.use("/graphql", graphql({ db, schema }));

export default app;
