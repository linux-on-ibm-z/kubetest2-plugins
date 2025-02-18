package powervs

import (
	"encoding/json"
	"fmt"
	"os"
	"path"

	"github.com/spf13/pflag"

	"github.com/ppc64le-cloud/kubetest2-plugins/pkg/providers"
	"github.com/ppc64le-cloud/kubetest2-plugins/pkg/tfvars/powervs"
)

const (
	Name = "powervs"
)

var _ providers.Provider = &Provider{}

var PowerVSProvider = &Provider{}

type Provider struct {
	powervs.TFVars
}

func (p *Provider) Initialize() error {
	return nil
}

func (p *Provider) BindFlags(flags *pflag.FlagSet) {
	flags.StringVar(
		&p.ResourceGroup, "powervs-resource-group", "Default", "IBM Cloud resource group name(command: ibmcloud resource groups)",
	)
	flags.StringVar(
		&p.DNSName, "powervs-dns", "", "IBM Cloud DNS name(command: ibmcloud dns instances)",
	)
	flags.StringVar(
		&p.DNSZone, "powervs-dns-zone", "", "IBM Cloud DNS Zone name(commmand: ibmcloud dns zones)",
	)
	flags.StringVar(
		&p.Apikey, "powervs-api-key", "", "IBM Cloud API Key used for accessing the APIs",
	)
	flags.StringVar(
		&p.Region, "powervs-region", "", "IBM Cloud PowerVS region name",
	)
	flags.StringVar(
		&p.Zone, "powervs-zone", "", "IBM Cloud PowerVS zone name",
	)
	flags.StringVar(
		&p.ServiceID, "powervs-service-id", "", "IBM Cloud PowerVS service instance ID(get GUID from command: ibmcloud resource service-instances --long)",
	)
	flags.StringVar(
		&p.NetworkName, "powervs-network-name", "", "Network Name(command: ibmcloud pi subnet ls)",
	)
	flags.StringVar(
		&p.ImageName, "powervs-image-name", "", "Image ID(command: ibmcloud pi img ls)",
	)
	flags.Float64Var(
		&p.Memory, "powervs-memory", 8, "Memory in GBs",
	)
	flags.Float64Var(
		&p.Processors, "powervs-processors", 0.5, "Processor Units",
	)
	flags.StringVar(
		&p.SSHKey, "powervs-ssh-key", "", "PowerVS SSH Key to authenticate LPARs",
	)
}

func (p *Provider) DumpConfig(dir string) error {
	filename := path.Join(dir, Name+".auto.tfvars.json")
	config, err := json.MarshalIndent(p.TFVars, "", "  ")
	if err != nil {
		return fmt.Errorf("errored file converting config to json: %v", err)
	}
	err = os.WriteFile(filename, config, 0644)
	if err != nil {
		return fmt.Errorf("failed to dump the json config to: %s, err: %v", filename, err)
	}
	return nil
}
