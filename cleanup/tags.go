package main

import (
	"log"
	"reflect"
	"strconv"
	"time"
)

// Some reflection. The SDK has a separate but identical Tag struct for each service.
func getTag(lookupKey string, tags interface{}) string {
	slice := reflect.ValueOf(tags)
	if slice.Kind() != reflect.Slice {
		log.Printf("getTag requires a slice (not %T)", tags)
		return ""
	}

	isPtrToString := func(v reflect.Value) bool {
		return v.Kind() == reflect.Ptr && v.Elem().Kind() == reflect.String
	}

	for i := 0; i < slice.Len(); i++ {
		tag := slice.Index(i)
		if tag.Kind() != reflect.Struct {
			log.Printf("getTag requires a slice of structs (not []%T)", tag)
			return ""
		}

		key := tag.FieldByName("Key")
		if !key.IsValid() || !isPtrToString(key) {
			log.Printf("getTag requires a Tag struct with field `Key` of type *string (not %+v)", tag)
			return ""
		}
		if lookupKey != key.Elem().String() {
			continue
		}

		val := tag.FieldByName("Value")
		if !val.IsValid() || !isPtrToString(val) {
			log.Printf("getTag requires a Tag struct with field `Value` of type *string (not %T)", key)
			return ""
		}
		return val.Elem().String()
	}
	return ""
}

func isOldBuildTime(timestamp string) bool {
	if unixTime, err := strconv.Atoi(timestamp); err == nil {
		buildTime := time.Unix(int64(unixTime), 0)
		return buildTime.Before(time.Now().Add(-resourceAge))
	}
	log.Printf("warning: unable to parse build time: %q", timestamp)
	return false
}
