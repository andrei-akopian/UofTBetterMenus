# University of Toronto Food Services Online (FSO) Menu API Documentation

## 1. Overview & Architecture

The University of Toronto Dining Services publishes meal menus and nutritional information through an ASP.NET MVC / DevExpress web application hosted at:
```
https://fso.ueat.utoronto.ca/FSO/ServiceMenuReport
```

Although the service does not expose a formal JSON/REST API, it operates on a set of HTTP endpoints returning server-rendered HTML partials and embedded serialized state. The frontend uses jQuery AJAX and DevExpress client scripts to swap DOM elements dynamically.

---

## 2. Core Concepts & Identifiers

- **Date format**: `YYYYMMDD` (e.g. `20261020` for October 20, 2026).
- **Unit / Dining Hall**: A campus location. The primary dining halls are:
  - `New College Dining Hall` (slug: `new-college`)
  - `Chestnut Residence` (slug: `chestnut`)
  - `CampusOne Dining Hall` (slug: `campus-one`)
  - `Oak House Dining Hall` (slug: `oak-house`)
  - `Medical Science Building (MSB) Cafeteria` (slug: `msb`)
  - Other locations include `Robarts Cafeteria` and `Sidney Smith Cafeteria`.
- **Meal**: A meal period within a day (e.g. `Breakfast`, `Lunch`, `Dinner`).
- **Menu UUID (`menu_id`)**: A unique UUID identifying a specific dining hall's menu for a specific meal on a given date (e.g., `b8771056-963d-4af3-825a-4e254b47561a` for New College Lunch on Oct 20).
- **Line UUID (`line_id`)**: A unique UUID identifying a specific dish / line item within that meal (e.g., `b4d6d8d1-39a3-4ce6-a5d0-be47eb3220f1` for Egg Salad).

---

## 3. Endpoints Reference

### 3.1. Date Shell & Location Hierarchy
* **Endpoint:** `GET /FSO/ServiceMenuReport/GetDate?dt={YYYYMMDD}`
* **Method:** `GET`
* **Query Parameters:**
  * `dt` (string, required): Date in format `YYYYMMDD`.
* **Description:** Loads the primary menu page for the selected date.
* **Returned Data:**
  * HTML page embedding DevExpress client objects.
  * The object `mnuUnits` / `navUnits` contains a base64-encoded `stateObject.itemsInfo` string.
  * **Decoding `itemsInfo`:**
    * Encoded with DevExpress type tags (`0x02` = String length + payload; `0x07` = Count of items / struct).
    * Contains the mapping of each Dining Hall $\to$ Meal Period $\to$ Menu UUID for that day.
    * Example decoded structure:
      ```
      CampusOne Dining Hall:
        Breakfast -> 6fdb2a91-b6b8-48a2-8a22-906540d28934
        Lunch     -> b380167a-8ec3-4e01-8c9f-c4b992d1b30a
        Dinner    -> bfe568a7-85d1-4b47-8ab0-055ef463a333
      New College Dining Hall:
        Breakfast -> 3508c16b-5840-4b57-a13e-4583da87a023
        Lunch     -> b8771056-963d-4af3-825a-4e254b47561a
        Dinner    -> 4cba0f1d-e901-4fe3-a58b-ad0fb16f2efd
      ```

---

### 3.2. Menu & Food Items Report
* **Endpoint:** `POST /FSO/ServiceMenuReport/GetReport/{menu_uuid}`
* **Method:** `POST` (or `GET`)
* **Path Parameters:**
  * `menu_uuid` (string, required): The UUID of the meal menu.
* **Form Body:**
  * `allergens` (string, optional): Comma-separated allergen filters.
  * `tags` (string, optional): Dietary preference filters (e.g. Vegetarian, Halal).
  * `maycontain` (string, optional): May-contain allergen filters.
* **Description:** Returns an HTML partial `<div class="nutritionReport">` containing the entire food menu for that meal.
* **Extracted Fields per Dish:**
  * **Station / Category:** Defined in `<tr><td class="courseHeader">Station Name</td></tr>` (e.g. *Grill*, *Salad Bar*, *Deli Bar*, *Lunch Entree*, *Pizza and Bake Station*, *Dessert*, *Soup*).
  * **Dish Name:** Inside `<td class="description">Dish Name</td>`.
  * **Line UUID (`line_id`):** Present in the `onclick` attribute of `<td class="description">`:
    ```javascript
    MenuItemClick(this, 'Egg Salad', 'b8771056-963d-4af3-825a-4e254b47561a', 'b4d6d8d1-39a3-4ce6-a5d0-be47eb3220f1');
    ```
  * **Serving Size:** `<td class="uom">100g</td>`.
  * **Macro & Micronutrients:** Table columns provide:
    1. Calories (kcal)
    2. Fat (g)
    3. Saturated Fat (g)
    4. Cholesterol (mg)
    5. Sodium (mg)
    6. Carbohydrates (g)
    7. Total Fibre (g)
    8. Sugars (g)
    9. Protein (g)
    10. Vitamin C (mg)
    11. Calcium (mg)
    12. Iron (mg)

---

### 3.3. Nutrition Facts, Ingredients & Allergen Label
* **Endpoint:** `POST /FSO/ServiceMenuReport/GetLabel/{menu_uuid}/{line_uuid}`
* **Method:** `POST` (also accepts empty form body `allergens=&tags=&maycontain=`)
* **Path Parameters:**
  * `menu_uuid` (string, required): The meal menu UUID.
  * `line_uuid` (string, required): The line item dish UUID.
* **Description:** Returns an HTML snippet formatting the official Canadian nutrition label popup for that item.
* **Extracted Fields:**
  * **Serving Size & Description:** (e.g., `Per 100g Serving`).
  * **Daily Values (% DV):** Fat, Saturated, Fibre, Sugars, Sodium, Calcium, Iron.
  * **Full Ingredients:**
    ```html
    <tr><td colspan="2"><b>Ingredients:</b> Pillow Pack Boiled Egg (Hard Cooked Eggs, Citric Acid, Sodium Benzoate...), Mayonnaise Vegan (...), Celery, Salt</td></tr>
    ```
  * **Allergens:**
    ```html
    <tr><td colspan="2"><b>Allergens:</b> Egg</td></tr>
    ```
  * **May Contain Warnings:**
    ```html
    <tr><td colspan="2"><b>May Contain:</b> None</td></tr>
    ```
  * **Dietary Tags:**
    ```html
    <tr><td colspan="2"><b>Tags:</b> Vegetarian</td></tr>
    ```

---

### 3.4. Filtered Report
* **Endpoint:** `POST /FSO/ServiceMenuReport/FilterReport/{menu_uuid}`
* **Method:** `POST`
* **Form Body:**
  * `allergens`: String (e.g. `Egg`)
  * `tags`: String (e.g. `Vegetarian`)
  * `maycontain`: String
* **Description:** Behaves identically to `GetReport/{menu_uuid}` with filter parameters applied server-side.

---

## 4. Reverse Engineered Workflow for Custom Clients

1. **Date Resolution**: Given date `YYYYMMDD`, query `GetDate?dt=YYYYMMDD`.
2. **Decode Hierarchy**: Extract the `stateObject.itemsInfo` base64 payload from `mnuUnits` and decode the binary DevExpress protocol to obtain each hall's meal menu UUIDs.
3. **Fetch Meal Dishes**: Call `GetReport/{menu_uuid}` to retrieve all stations and food items with macro data and `line_id`s.
4. **Fetch Allergens & Details**: Call `GetLabel/{menu_uuid}/{line_id}` to retrieve allergen tags, ingredients, and detailed nutritional facts.
5. **Caching Strategy**: Since menus rarely change after publishing for a given day, results can be cached in-memory by `(dining_hall, date, meal)` tuple for rapid performance and offline resilience.
