import { mountApp } from "./App";
import "./styles.css";

const app = document.getElementById("app");

if (app instanceof HTMLElement) {
  mountApp(app);
}
