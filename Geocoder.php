<?php

class Geocoder {
  public function __construct() {
    $this->base_url = "http://maps.googleapis.com/maps/api/geocode/json?sensor=false";
    $this->address  = array();
    $this->address_csv = "";
    $this->lat = 0;
    $this->lng = 0;
  }

  public function geocode($postcode) {
    $postcode = str_replace(" ", "", $postcode);
    $url = $this->base_url . "&address=" . urlencode($postcode . ", UK");

    $result = $this->_make_request($url);

    if($result) {
      $result = json_decode($result);

      if(count($result->results) == 0) {
        return false;
      }

      if(count($result->results)) {
        $r = $result->results[0];
        $this->address_csv = $r->formatted_address;

        foreach($r->address_components as $ac) {
          foreach($ac->types as $typ) {
            $this->address[$typ] = $ac->long_name;
          }
        }

        $bounds = null;


        if(isset($r->geometry->bounds)) {
          $bounds = $r->geometry->bounds;
          $this->lat = ($bounds->northeast->lat + $bounds->southwest->lat) / 2;
          $this->lng = ($bounds->northeast->lng + $bounds->southwest->lng) / 2;
        } elseif(isset($r->geometry->location)) {
          $bounds = $r->geometry->location;
          $this->lat = $bounds->lat;
          $this->lng = $bounds->lng;
        } else {
          $this->lat = 0;
          $this->lng = 0;
        }
      }
    }

    $parts = array();
    if(array_key_exists("locality",$this->address)) {
      $parts[] = $this->address["locality"];
    }

    if(array_key_exists("postal_town",$this->address)) {
      $parts[] = $this->address["postal_town"];
    }

    if(array_key_exists("administrative_area_level_2",$this->address)) {
      $parts[] = $this->address["administrative_area_level_2"];
    }

    $parts = array_values(array_unique($parts));

    if(count($parts) == 1) {
      $this->address_csv = $parts[0];
    } elseif(count($parts) > 1) {
      if(strpos($parts[1],$parts[0]) > 0) {
        unset($parts[1]);

        $this->address_csv = $parts[0];
      } else {
        $this->address_csv = $parts[0] . ", " . $parts[count($parts)-1];
      }
    }

    if(count($parts) > 0) {
      $postcode_start = substr($postcode,0,strlen($postcode)-3);
      $this->address_csv = $this->address_csv . ", " . $postcode_start;
    } else {
      $this->address_csv = "";
    }

    return true;
  }

  private function _make_request($url) {
    $ch = curl_init();
    curl_setopt($ch,CURLOPT_URL, $url);
    curl_setopt($ch,CURLOPT_RETURNTRANSFER, 1);
    $output = curl_exec($ch);
    curl_close($ch);
    return $output;
  }
}

?>
