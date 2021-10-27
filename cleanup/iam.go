package main

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/iam"
	"github.com/hashicorp/go-multierror"
)

type IamRole struct {
	id                       string
	name                     string
	instanceProfileNames     []string
	managedPoliciesAtttached string
}

func (i IamRole) String() string {
	return fmt.Sprintf("id=%s name=%s instanceProfiles=%s",
		i.id, i.name, i.instanceProfileNames)
}

func (i IamRole) Delete() error {
	panic("implement me")
}

func (i IamRole) Wait() error {
	panic("implement me")
}

func ListIamRoles(cfg aws.Config, ctx context.Context, resourceChan chan Resource) error {
	log.Printf("Listing IAM roles")

	iamClient := iam.NewFromConfig(cfg)
	pager := iam.NewListRolesPaginator(iamClient, nil)

	var errors error

	// This is horrible. There's no way to filter by name. And we seem to hit rate limits
	// all the time in our account.
	for pager.HasMorePages() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return err
		}

		for _, role := range page.Roles {
			if strings.Index(*role.RoleName, "consul-ecs") != 0 {
				continue
			}

			tags, err := iamClient.ListRoleTags(ctx, &iam.ListRoleTagsInput{
				RoleName: role.RoleName,
			})
			if err != nil {
				errors = multierror.Append(errors, err)
				continue
			}

			buildUrl := getTag(buildUrlTagName, tags.Tags)
			buildTime := getTag(buildTimeTagName, tags.Tags)
			if strings.Contains(buildUrl, buildUrlPrefix) && isOldBuildTime(buildTime) {
				resourceChan <- IamRole{
					id:                   *role.RoleId,
					name:                 *role.RoleName,
					instanceProfileNames: listInstanceProfiles(iamClient, ctx, *role.RoleName),
					// managedPoliciesAtttached: "",
				}
			}
		}

	}
	return errors
}

func listInstanceProfiles(iamClient *iam.Client, ctx context.Context, roleName string) []string {
	log.Printf("Listing instance profiles for role %s", roleName)
	profiles, err := iamClient.ListInstanceProfilesForRole(ctx, &iam.ListInstanceProfilesForRoleInput{
		RoleName: aws.String(roleName),
	})
	if err != nil {
		log.Printf("warning: error listing instance profiles for role: %s", err)
		return nil
	}

	var profileNames []string
	for _, profile := range profiles.InstanceProfiles {
		profileNames = append(profileNames, *profile.InstanceProfileName)
	}
	return profileNames
}
