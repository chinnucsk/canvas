
-record(user, {ip_addr}).
-record(line, {coords, size, color, user}).

%% Postgres db info
-define(ls_store_host,  "localhost").
-define(ls_store_db,    "mochi_test").
-define(ls_store_user,  "mochi_test").
-define(ls_store_pass,  "").