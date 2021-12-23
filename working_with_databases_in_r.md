Database Primer in R
================
Brandon Farr
2021-12-23

## Ensure Database Integrity: Primary Key and Foreign Keys

Create a database with two tables: `parent` and `child`. Create a
relationship between the two tables using `PRIMARY KEY` and
`FOREIGN KEY` to:

-   ensure all entries in `child` relate to an **existing** record in
    `parent`
-   ensure that when an entry in `parent` is deleted, all related
    records in `child` are deleted

This chunk references `DROP_PARENTCHILDDB_SCHEMA.SQL` as input to clear
the schema for new use in this script.

``` bash
sqlite3 PARENTCHILDDB < DROP_PARENTCHILDDB_SCHEMA.SQL
#> Dropping PARENTCHILDDB schema objects...
```

This chunk references `CREATE_PARENTCHILDDB_SCHEMA.SQL` as input to
create all of the schema objects for `PARENTCHILDDB`.

``` bash
sqlite3 PARENTCHILDDB < CREATE_PARENTCHILDDB_SCHEMA.SQL
#> Creating SAMPLEDB schema objects...
```

First, setup the connection object in R, so that you can interact with
the database.

``` r
base_dir <- here::here()
db_file <- fs::path(base_dir, "PARENTCHILDDB")

if(dbCanConnect(RSQLite::SQLite(), db_file)) {
    parentchilddb <- dbConnect(RSQLite::SQLite(), db_file)
}
```

The next chunk - which is an `r` chunk - uses the `RSQLite` function
`dbListTables` to verify that the tables have been created.

``` r
dbListTables(parentchilddb)
#> [1] "child"  "parent"

dbListFields(parentchilddb, "parent")
#> [1] "uid"         "parent_name"

dbListFields(parentchilddb, "child")
#> [1] "parent_uid" "child_name"
```

Now, write some data into the `parent` table.

``` r
parent_tbl <- tibble(
    uid = 1:2,
    parent_name = c("Adam", "Jacob")
)

dbAppendTable(parentchilddb, "parent", parent_tbl)
#> [1] 2
```

As a brief aside, let’s define a function via our friend [H. David
Shea](https://github.com/hdshea/) that makes querying database tables
much easier in R. The main benefit is that the result is in a `tibble`.

``` r
db_select_data <- function(con, select_statement ) {
    res <- dbSendQuery(con, select_statement)
    rval <- tibble::tibble(dbFetch(res)) %>%
        mutate(across(contains("_date"), as.Date, origin = "1970-01-01"))
    dbClearResult(res)
    rm(res)
    rval
}
```

Now, use `db_select_data` to look at what is in the `parent` table.

``` r
db_select_data(parentchilddb, "SELECT * FROM parent;")
#> # A tibble: 2 × 2
#>     uid parent_name
#>   <int> <chr>      
#> 1     1 Adam       
#> 2     2 Jacob
```

Let’s add a record in `child` that does not violate the FOREIGN KEY
constraint.

``` r
good_child_tbl <- tibble(
    parent_uid = 1,
    child_name = "Abel"
)

dbAppendTable(parentchilddb, "child", good_child_tbl)
#> [1] 1

db_select_data(parentchilddb, "SELECT * FROM child;")
#> # A tibble: 1 × 2
#>   parent_uid child_name
#>        <int> <chr>     
#> 1          1 Abel
```

As it currently stands is the database going to enforce integrity? Try
inserting a child with a `parent_uid` that is not in `parent`.

``` r
bad_child_tbl <- tibble(
    parent_uid = 3,
    child_name = "Solomon"
)

dbAppendTable(parentchilddb, "child", bad_child_tbl)
#> [1] 1

db_select_data(parentchilddb, "SELECT * FROM child;")
#> # A tibble: 2 × 2
#>   parent_uid child_name
#>        <int> <chr>     
#> 1          1 Abel      
#> 2          3 Solomon
```

### Enforce integrity with `PRAGMA foreign_keys = ON;`

Looks like the record was added, against our expectations. What
happened? Well, looks like `sqlite3` doesn’t automatically enforce
`FOREIGN KEY` integrity unless during the connection session, you set a
`PRAGMA`. So, let’s drop the current connection and set up a new one.

``` r
# disconnect from current session
dbDisconnect(parentchilddb)

# reconnect and immediately make a PRAGMA call
if(dbCanConnect(RSQLite::SQLite(), db_file)) {
    parentchilddb <- dbConnect(RSQLite::SQLite(), db_file)
    
    # insure foreign keys are enforced
    rs <- dbSendStatement(parentchilddb, "PRAGMA foreign_keys = ON;")
    dbHasCompleted(rs)
    dbClearResult(rs)
}
```

Now, try to insert a problematic record.

``` r
another_bad_child_tbl <- tibble(
    parent_uid = 4,
    child_name = "Samuel"
)

safe_dbAppendTable <- safely(dbAppendTable)

safe_dbAppendTable(parentchilddb, "child", another_bad_child_tbl)
#> $result
#> NULL
#> 
#> $error
#> <Rcpp::exception: FOREIGN KEY constraint failed>

db_select_data(parentchilddb, "SELECT * FROM child;")
#> # A tibble: 2 × 2
#>   parent_uid child_name
#>        <int> <chr>     
#> 1          1 Abel      
#> 2          3 Solomon
```

That’s more like it. Let’s reset the database and test what happens when
parents are deleted.

``` bash
sqlite3 PARENTCHILDDB < DROP_PARENTCHILDDB_SCHEMA.SQL
sqlite3 PARENTCHILDDB < CREATE_PARENTCHILDDB_SCHEMA.SQL

#> Dropping PARENTCHILDDB schema objects...
#> Creating SAMPLEDB schema objects...
```

``` r
# add parents back into `parent` table
safe_dbAppendTable(parentchilddb, "parent", parent_tbl)
#> $result
#> [1] 2
#> 
#> $error
#> NULL

fill_children_tbl <- tibble(
    parent_uid = c(1, 1, rep(2, 13)),
    child_name = c(
        "Cain", "Abel",
        "Reuben", "Simeon", "Levi", "Judah",
        "Dan", "Naphtali", "Gad", "Asher",
        "Issachar", "Zebulun", "Dinah", "Joseph",
        "Benjamin"
    )
)

safe_dbAppendTable(parentchilddb, "child", fill_children_tbl)
#> $result
#> [1] 15
#> 
#> $error
#> NULL

db_select_data(parentchilddb, "SELECT * FROM child;")
#> # A tibble: 15 × 2
#>    parent_uid child_name
#>         <int> <chr>     
#>  1          1 Cain      
#>  2          1 Abel      
#>  3          2 Reuben    
#>  4          2 Simeon    
#>  5          2 Levi      
#>  6          2 Judah     
#>  7          2 Dan       
#>  8          2 Naphtali  
#>  9          2 Gad       
#> 10          2 Asher     
#> 11          2 Issachar  
#> 12          2 Zebulun   
#> 13          2 Dinah     
#> 14          2 Joseph    
#> 15          2 Benjamin
```

### Cascading DELETEs

A key scenario to test for when determining database integrity is the
deletion of children records related to a deleted parent. Does `sqlite3`
accomplish this? Let’s try removing `Jacob` and see what happens.

``` r
safe_dbSendStatement <- safely(dbSendStatement)

safe_dbSendStatement(
    parentchilddb,
    "DELETE FROM parent WHERE parent_name = 'Jacob'"
)
#> $result
#> <SQLiteResult>
#>   SQL  DELETE FROM parent WHERE parent_name = 'Jacob'
#>   ROWS Fetched: 0 [complete]
#>        Changed: 14
#> 
#> $error
#> NULL
# if(dbHasCompleted(res)) {
#     dbGetRowsAffected(res)
# }
# dbClearResult(res)


db_select_data(parentchilddb, "SELECT * from parent;")
#> Warning: Closing open result set, pending rows
#> # A tibble: 1 × 2
#>     uid parent_name
#>   <int> <chr>      
#> 1     1 Adam

db_select_data(parentchilddb, "SELECT * from child;")
#> # A tibble: 2 × 2
#>   parent_uid child_name
#>        <int> <chr>     
#> 1          1 Cain      
#> 2          1 Abel
```

## Summary

What did we learn in this exercise?

> Creating and maintaining database integrity is a two-step process in
> sqlite3.

1.  Proper schema setup using `FOREIGN KEY`, `REFERENCE` and `ON UPDATE`

``` sql
CREATE TABLE IF NOT EXISTS child
(
    parent_uid INTEGER NOT NULL,
    child_name TEXT NOT NULL,
    FOREIGN KEY(parent_uid)
        REFERENCES parent(uid)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);
```

1.  When connecting to the database use `PRAGMA foreign_keys = ON;`

``` r

if(dbCanConnect(RSQLite::SQLite(), db_file)) {
    parentchilddb <- dbConnect(RSQLite::SQLite(), db_file)
    
    # insure foreign keys are enforced
    rs <- dbSendStatement(parentchilddb, "PRAGMA foreign_keys = ON;")
    dbHasCompleted(rs)
    dbClearResult(rs)
}
```
