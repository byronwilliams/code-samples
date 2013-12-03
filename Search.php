<?php

class Search extends Eloquent {
  public static $table = "searches";

  public $results = array();

  public function fulltext($q) {
    $this->s_filters["fulltext"] = $q;

    $es = new FullTextSearch();
    $params = array();
    $params["type"] = "something";
    $params["size"] = 100;

    if(strlen($q)) {
      $params["body"]["query"]["multi_match"]["query"] = $q;
      $params["body"]["query"]["multi_match"]["fields"][] = "title^2";
      $params["body"]["query"]["multi_match"]["fields"][] = "description";
      $params["body"]["query"]["multi_match"]["fields"][] = "company_name";
      $params["body"]["query"]["multi_match"]["fields"][] = "skill_tags^2";
      $params["body"]["query"]["multi_match"]["operator"] = "and";
    }

    $params["body"]["fields"][] = "_id";
    $params["body"]["filter"]["range"]["display_to"]["gte"] = date("Y-m-d");

    $res = $es->search($params);

    $jobs = array_map(function($hit) {
                     return (int) $hit["_id"];
    },$res["hits"]["hits"]);

    $this->fulltext_results = $jobs;

    return $this;
  }

  public function location($l,$u_radius=10) {
    $this->s_filters["location"] = $l;

    $u_radius = (int) $u_radius;
    if(!in_array($u_radius, array(10,15,20,25))) {
      $u_radius = 10;
    }

    $lat = 54.17143;
    $lng = -4.13085;
    $radius = 375;

    if(strlen($l) > 0) {
      $gc = new Geocoder();
      $res = $gc->geocode($l);

      if($res) {
        $lat = $gc->lat;
        $lng = $gc->lng;
        $radius = $u_radius;
      }
    }

    $jobs = JobLocation::filter(array(
                                "loc" => array(
                                               "\$geoWithin" => array(
                                                                     "\$centerSphere" => array(
                                                                                              array($lat,$lng),
                                                                                              $radius / 3959
                                                                                              )
                                                                     )
                                               )
                                ));

    $this->location_results = $jobs;

    return $this;
  }

  public function of_type($types) {
    $this->s_filters["types"] = $types;
    return $this;
  }

  public function per_page($n) {
    $this->s_filters["pp"] = $n;
    return $this;
  }

  public function page($n) {
    $n = $n - 1;
    $this->s_filters["p"] = $n;
    return $this;
  }

  public function paginate() {
    $this->results = array_intersect($this->fulltext_results, $this->location_results);

    if(count($this->results)) {
      $this->_total_results = count($this->results);

      $jq = Job::where_in("id",$this->results)
                ->where("is_posted","=",true)
                ->where("display_to",">=",date(FORMAT_MYSQL_DATETIME));

      if(isset($this->s_filters["types"]) && count($this->s_filters["types"])) {
        $jq->where_in("type",$this->s_filters["types"]);
      }

      $jq->order_by("display_to");

      if($this->s_filters["pp"] != 0) {
        $jq->take($this->s_filters["pp"])
           ->skip($this->s_filters["pp"]*$this->s_filters["p"]);
      }

      $this->results = $jq->get();
    } else {
      $this->results = array();
    }

    return $this;
  }

  public function get_page_count() {
    if($this->s_filters["pp"] == 0) {
      return 1;
    } else {
      return floor($this->_total_results / $this->s_filters["pp"]);
    }
  }

  public function save() {
    $user_id = 0;

    if(Sentry::check()) {
      $user_id = Sentry::user()->id;
    }

    $this->set_attribute("user_id",$user_id);
    $this->set_attribute("type","job");
    $this->set_attribute("count",count($this->result_ids));

    $s = parent::save();

    foreach($this->s_filters as $filter_key => $filter_val) {
      $f = new SearchFilter();

      if(gettype($filter_val) == "array") {
        foreach($filter_val as $v) {
          $f->create(array(
                            "search_id" => $this->id,
                            "k" => $filter_key,
                            "v" => $v
                            ));
        }
      } else {
        $f->create(array(
                          "search_id" => $this->id,
                          "k" => $filter_key,
                          "v" => $filter_val
                          ));
      }
    }
  }

  public static function fmt_permalink($p) {
    $permalink = strtolower($p);
    $permalink = preg_replace("/[^a-z0-9\-\.\+]/i","-",$permalink);
    $words = array("a","in","for","to","and","at","ltd","limited","plc");
    $concise = preg_replace("/\b(".implode("|",$words).")\b/","-",$permalink);
    $concise = trim(preg_replace("/[-]+/","-",$concise),"-");
    return $concise;
  }


  private $fulltext_results = array();
  private $location_results = array();
  private $s_filters = array(
                             "pp" => 10,
                             "p" => 1,
                             "type" => array()
                             );
  private $_total_results = 0;
}

?>
