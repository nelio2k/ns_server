%% @author Couchbase <info@couchbase.com>
%% @copyright 2011 Couchbase, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%      http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
-module(capi_view).

-include("couch_db.hrl").
-include("couch_view_merger.hrl").
-include("ns_common.hrl").

-export([handle_view_req/3]).
-export([all_docs_db_req/2]).

-import(couch_util, [
    get_value/2,
    get_value/3
]).

design_doc_view(Req, Db, DesignName, ViewName) ->
    DDocId = <<"_design/", DesignName/binary>>,
    MergeParams = view_merge_params(Req, Db, DDocId, ViewName),
    couch_view_merger:query_view(Req, MergeParams).


handle_view_req(Req, Db, DDoc) when Db#db.filepath =/= undefined ->
    couch_httpd_view:handle_view_req(Req, Db, DDoc);

handle_view_req(#httpd{method='GET',
        path_parts=[_, _, DName, _, ViewName]}=Req, Db, _DDoc) ->
    design_doc_view(Req, Db, DName, ViewName);

handle_view_req(#httpd{method='POST',
        path_parts=[_, _, DName, _, ViewName]}=Req, Db, _DDoc) ->
    couch_httpd:validate_ctype(Req, "application/json"),
    design_doc_view(Req, Db, DName, ViewName);

handle_view_req(Req, _Db, _DDoc) ->
    couch_httpd:send_method_not_allowed(Req, "GET,POST,HEAD").


all_docs_db_req(Req, #db{filepath = undefined} = Db) ->
    MergeParams = view_merge_params(Req, Db, nil, <<"_all_docs">>),
    couch_view_merger:query_view(Req, MergeParams);

all_docs_db_req(Req, Db) ->
    couch_httpd_db:db_req(Req, Db).


node_vbuckets_dict(BucketName) ->
    {ok, BucketConfig} = ns_bucket:get_bucket(BucketName),
    Map = get_value(map, BucketConfig, []),
    {_, NodeToVBuckets} =
        lists:foldl(fun([Master | _], {Idx, Dict}) ->
            {Idx + 1, dict:append(Master, Idx, Dict)}
        end, {0, dict:new()}, Map),
    NodeToVBuckets.


view_merge_params(Req, #db{name = BucketName}, DDocId, ViewName) ->
    NodeToVBuckets = node_vbuckets_dict(?b2l(BucketName)),
    Config = ns_config:get(),
    FullViewName = case DDocId of
    nil ->
        % _all_docs and other special builtin views
        ViewName;
    _ ->
        iolist_to_binary([DDocId, $/, ViewName])
    end,
    ViewSpecs = dict:fold(
        fun(Node, VBuckets, Acc) when Node =:= node() ->
            build_local_specs(BucketName, DDocId, ViewName, VBuckets) ++ Acc;
        (Node, VBuckets, Acc) ->
           [build_remote_specs(Node, BucketName, FullViewName, VBuckets, Config) | Acc]
        end, [], NodeToVBuckets),
    case Req#httpd.method of
    'GET' ->
        Body = [],
        Keys = validate_keys_param(couch_httpd:qs_json_value(Req, "keys", nil));
    'POST' ->
        {Body} = couch_httpd:json_body_obj(Req),
        Keys = validate_keys_param(get_value(<<"keys">>, Body, nil))
    end,
    MergeParams0 = #view_merge{
        views = ViewSpecs,
        keys = Keys
    },
    couch_httpd_view_merger:apply_http_config(Req, Body, MergeParams0).


validate_keys_param(nil) ->
    nil;
validate_keys_param(Keys) when is_list(Keys) ->
    Keys;
validate_keys_param(_) ->
    throw({bad_request, "`keys` parameter is not an array."}).


vbucket_db_name(BucketName, VBucket) ->
    iolist_to_binary([BucketName, $/, integer_to_list(VBucket)]).


build_local_specs(BucketName, DDocId, ViewName, VBuckets) ->
    lists:map(fun(VBucket) ->
            #simple_view_spec{
                database = vbucket_db_name(BucketName, VBucket),
                ddoc_id = DDocId,
                view_name = ViewName
            }
        end, VBuckets).


build_remote_specs(Node, BucketName, FullViewName, VBuckets, Config) ->
    MergeURL = iolist_to_binary(capi_utils:capi_url(Node, "/_view_merge", "127.0.0.1", Config)),
    Props = {[
        {<<"views">>,
            {[{vbucket_db_name(BucketName, VBId), FullViewName} || VBId <- VBuckets]}}
    ]},
    #merged_view_spec{url = MergeURL, ejson_spec = Props}.
